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
#include <aws/auth/auth.h>
#include <aws/auth/credentials.h>
#include <aws/io/io.h>
#include <aws/dsql-auth/auth_token.h>
#include <aws/sdkutils/sdkutils.h>

static bool aws_libs_initialized = false;

/*
 * This function can be called to clean up AWS library resources
 */
static void
_dsql_auth_cleanup(void)
{
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
 * Clean up DSQL authentication resources
 */
void
dsql_auth_cleanup(void)
{
    _dsql_auth_cleanup();
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
        aws_auth_library_init(allocator);
        aws_sdkutils_library_init(allocator);
        aws_libs_initialized = true;
        
        /* Note: We cannot use atexit() in libpq as it's not allowed to call exit-related functions.
         * The cleanup will be handled by explicit calls at application shutdown or by the OS.
         */
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
    
    /* Initialize AWS libraries */
    initialize_aws_libs();
    
    allocator = aws_default_allocator();
    
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
        aws_region = aws_string_new_from_c_str(allocator, env_region);
        if (!aws_region) {
            if (err_msg)
                *err_msg = strdup("Failed to create region string from AWS_REGION");
            goto cleanup;
        }
    }
    else
    {
        /* Try to infer region from hostname */
        if (aws_dsql_auth_config_infer_region(allocator, &auth_config, &aws_region) != AWS_OP_SUCCESS ||
            aws_region == NULL)
        {
            if (err_msg)
                *err_msg = strdup("Failed to infer AWS region from hostname. Please set AWS_REGION environment variable.");
            goto cleanup;
        }
    }
    aws_dsql_auth_config_set_region(&auth_config, aws_region);
    
    /* Create default credentials provider */
    AWS_ZERO_STRUCT(credentials_options);
    
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
