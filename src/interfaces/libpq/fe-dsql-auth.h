/*
 * fe-dsql-auth.h
 *
 * Support for AWS DSQL authentication token generation
 *
 * Copyright (c) 2025 PostgreSQL Global Development Group
 */
#ifndef FE_DSQL_AUTH_H
#define FE_DSQL_AUTH_H

#include <stdbool.h>

/* Initialize the DSQL token generator */
int dsql_initialize_token_generator(void);

/* Generate a DSQL authentication token for the specified endpoint */
char *dsql_generate_token(const char *endpoint, bool admin, char **err_msg);

/* Initialize and validate AWS credentials early (for startup validation) */
int dsql_validate_aws_credentials(char **err_msg);

/* Clean up DSQL authentication resources */
void dsql_cleanup(void);

#endif /* FE_DSQL_AUTH_H */
