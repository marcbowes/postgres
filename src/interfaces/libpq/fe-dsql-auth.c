/*
 * fe-dsql-auth.c
 *
 * Support for AWS DSQL authentication token generation
 *
 * Copyright (c) 2025 PostgreSQL Global Development Group
 */
#include "postgres_fe.h"

#include "fe-dsql-auth.h"
#include "libpq-int.h"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <time.h>

/* Include AWS DSQL Auth library functions */
#include <aws/common/common.h>
#include <aws/common/logging.h>
#include <aws/auth/auth.h>
#include <aws/auth/credentials.h>
#include <aws/io/io.h>
#include <aws/io/event_loop.h>
#include <aws/io/host_resolver.h>
#include <aws/io/channel_bootstrap.h>
#include <aws/http/http.h>
#include <aws/dsql-auth/auth_token.h>
#include <aws/sdkutils/sdkutils.h>

static bool aws_libs_initialized = false;
static struct aws_logger dsql_logger;
static bool dsql_logger_initialized = false;

/* HTTP infrastructure for IMDS */
static struct aws_event_loop_group *s_el_group = NULL;
static struct aws_host_resolver *s_host_resolver = NULL;
static struct aws_client_bootstrap *s_client_bootstrap = NULL;

/*
 * Initialize DSQL logging
 */
static void
initialize_dsql_logging(void)
{
    if (!dsql_logger_initialized)
    {
        struct aws_allocator *allocator = aws_default_allocator();
        struct aws_logger_standard_options logger_options = {
            .level = AWS_LOG_LEVEL_DEBUG,  /* Can be controlled by environment variable */
            .file = stderr  /* Log to stderr by default */
        };
        
        /* Check for AWS_LOG_LEVEL environment variable */
        const char *log_level_str = getenv("AWS_LOG_LEVEL");
        if (log_level_str != NULL)
        {
            enum aws_log_level level;
            if (aws_string_to_log_level(log_level_str, &level) == AWS_OP_SUCCESS)
            {
                logger_options.level = level;
            }
        }
        
        /* Check for AWS_LOG_FILE environment variable for file output */
        const char *log_file_str = getenv("AWS_LOG_FILE");
        if (log_file_str != NULL && strlen(log_file_str) > 0)
        {
            if (strcmp(log_file_str, "stdout") == 0)
            {
                logger_options.file = stdout;
            }
            else if (strcmp(log_file_str, "stderr") == 0)
            {
                logger_options.file = stderr;
            }
            else
            {
                /* Use as a filename */
                logger_options.filename = log_file_str;
                logger_options.file = NULL;
            }
        }
        
        if (aws_logger_init_standard(&dsql_logger, allocator, &logger_options) == AWS_OP_SUCCESS)
        {
            aws_logger_set(&dsql_logger);
            dsql_logger_initialized = true;
        }
    }
}

/*
 * Clean up DSQL authentication resources
 */
void
dsql_auth_cleanup(void)
{
    if (dsql_logger_initialized)
    {
        aws_logger_set(NULL);
        aws_logger_clean_up(&dsql_logger);
        dsql_logger_initialized = false;
    }
    
    if (aws_libs_initialized)
    {
        aws_sdkutils_library_clean_up();
        aws_auth_library_clean_up();
        aws_io_library_clean_up();
        aws_common_library_clean_up();
        aws_libs_initialized = false;
    }
}

/*
 * Initialize AWS libraries if not already initialized
 */
static void
initialize_aws_libs(void)
{
    if (!aws_libs_initialized)
    {
        struct aws_allocator *allocator = aws_default_allocator();
        aws_common_library_init(allocator);
        aws_io_library_init(allocator);
        aws_http_library_init(allocator);
        aws_auth_library_init(allocator);
        aws_sdkutils_library_init(allocator);
        
        /* Initialize HTTP infrastructure for IMDS */
        AWS_LOGF_DEBUG(AWS_LS_AUTH_GENERAL, "Initializing HTTP infrastructure for IMDS");
        
        s_el_group = aws_event_loop_group_new_default(allocator, 1, NULL);
        if (!s_el_group) {
            AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to create event loop group");
            goto error;
        }
        
        struct aws_host_resolver_default_options resolver_options = {
            .el_group = s_el_group,
            .max_entries = 8,
        };
        s_host_resolver = aws_host_resolver_new_default(allocator, &resolver_options);
        if (!s_host_resolver) {
            AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to create host resolver");
            goto error;
        }
        
        struct aws_client_bootstrap_options bootstrap_options = {
            .event_loop_group = s_el_group,
            .host_resolver = s_host_resolver,
        };
        s_client_bootstrap = aws_client_bootstrap_new(allocator, &bootstrap_options);
        if (!s_client_bootstrap) {
            AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to create client bootstrap");
            goto error;
        }
        
        aws_libs_initialized = true;
        AWS_LOGF_DEBUG(AWS_LS_AUTH_GENERAL, "AWS libraries and HTTP infrastructure initialized successfully");
        
        /* Note: We cannot use atexit() in libpq as it's not allowed to call exit-related functions.
         * The cleanup will be handled by explicit calls at application shutdown or by the OS.
         */
        return;
        
    error:
        /* Clean up on error */
        if (s_client_bootstrap) {
            aws_client_bootstrap_release(s_client_bootstrap);
            s_client_bootstrap = NULL;
        }
        if (s_host_resolver) {
            aws_host_resolver_release(s_host_resolver);
            s_host_resolver = NULL;
        }
        if (s_el_group) {
            aws_event_loop_group_release(s_el_group);
            s_el_group = NULL;
        }
        AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to initialize AWS libraries");
    }
}

/*
 * Generate a DSQL authentication token for the specified endpoint.
 * Uses the AWS DSQL auth library to generate a real token.
 * Returns a newly allocated string containing the token.
 */
char *
generate_dsql_token(const char *endpoint, bool admin, char **err_msg)
{
    struct aws_allocator *allocator;
    struct aws_dsql_auth_config auth_config;
    struct aws_dsql_auth_token auth_token = {0};
    struct aws_string *aws_region = NULL;
    struct aws_credentials_provider *credentials_provider = NULL;
    struct aws_credentials_provider_chain_default_options credentials_options;
    char *token = NULL;
    int aws_error;
    const char *env_region;
    const char *token_str;
    
    /* Initialize AWS libraries and logging */
    initialize_aws_libs();
    initialize_dsql_logging();
    
    allocator = aws_default_allocator();
    
    AWS_LOGF_INFO(AWS_LS_AUTH_GENERAL, "Starting DSQL token generation for endpoint: %s", endpoint);
    
    /* Initialize DSQL auth config */
    if (aws_dsql_auth_config_init(&auth_config) != AWS_OP_SUCCESS) {
        if (err_msg)
            *err_msg = strdup("Failed to initialize DSQL auth config");
        goto cleanup;
    }
    
    /* Set hostname */
    aws_dsql_auth_config_set_hostname(&auth_config, endpoint);
    
    /* Try to get region from environment variable first */
    env_region = getenv("AWS_REGION");
    if (env_region != NULL && env_region[0] != '\0')
    {
        AWS_LOGF_DEBUG(AWS_LS_AUTH_GENERAL, "Using AWS_REGION from environment: %s", env_region);
        aws_region = aws_string_new_from_c_str(allocator, env_region);
        if (!aws_region) {
            AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to create region string from AWS_REGION");
            if (err_msg)
                *err_msg = strdup("Failed to create region string from AWS_REGION");
            goto cleanup;
        }
    }
    else
    {
        AWS_LOGF_DEBUG(AWS_LS_AUTH_GENERAL, "AWS_REGION not set, attempting to infer from hostname: %s", endpoint);
        /* Try to infer region from hostname */
        if (aws_dsql_auth_config_infer_region(allocator, &auth_config, &aws_region) != AWS_OP_SUCCESS ||
            aws_region == NULL)
        {
            AWS_LOGF_ERROR(AWS_LS_AUTH_GENERAL, "Failed to infer AWS region from hostname: %s", endpoint);
            if (err_msg)
                *err_msg = strdup("Failed to infer AWS region from hostname. Please set AWS_REGION environment variable.");
            goto cleanup;
        }
        AWS_LOGF_INFO(AWS_LS_AUTH_GENERAL, "Inferred region: %s", aws_string_c_str(aws_region));
    }
    aws_dsql_auth_config_set_region(&auth_config, aws_region);
    
    /* Create default credentials provider with client bootstrap for IMDS */
    AWS_ZERO_STRUCT(credentials_options);
    credentials_options.bootstrap = s_client_bootstrap;
    
    AWS_LOGF_DEBUG(AWS_LS_AUTH_GENERAL, "Creating credentials provider chain with bootstrap for IMDS");
    credentials_provider = aws_credentials_provider_new_chain_default(allocator, &credentials_options);
    if (!credentials_provider) {
        aws_error = aws_last_error();
        if (err_msg)
            *err_msg = strdup(aws_error_str(aws_error));
        goto cleanup;
    }
    
    /* Set credentials provider */
    aws_dsql_auth_config_set_credentials_provider(&auth_config, credentials_provider);
    
    /* Set expiration time to 5 seconds for shorter token lifetime */
    aws_dsql_auth_config_set_expires_in(&auth_config, 5); /* 5 seconds */

    /* Generate the token */
    AWS_ZERO_STRUCT(auth_token);
    if (aws_dsql_auth_token_generate(&auth_config, admin, allocator, &auth_token) != AWS_OP_SUCCESS)
    {
        aws_error = aws_last_error();
        if (err_msg)
            *err_msg = strdup(aws_error_str(aws_error));
        goto cleanup;
    }
    
    /* Get the token string */
    token_str = aws_dsql_auth_token_get_str(&auth_token);
    if (token_str)
    {
        token = strdup(token_str);
        /* Token generation successful */
    }
    else
    {
        if (err_msg)
            *err_msg = strdup("Failed to get token string");
    }
    
cleanup:
    aws_dsql_auth_token_clean_up(&auth_token);
    aws_dsql_auth_config_clean_up(&auth_config);
    
    if (credentials_provider)
    {
        aws_credentials_provider_release(credentials_provider);
    }
    
    if (aws_region)
    {
        aws_string_destroy(aws_region);
    }
    
    return token;
}
