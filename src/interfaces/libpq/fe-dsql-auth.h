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

/* Generate a DSQL authentication token for the specified endpoint */
char *generate_dsql_token(const char *endpoint, bool admin, char **err_msg);

/* Clean up DSQL authentication resources */
void dsql_auth_cleanup(void);

#endif /* FE_DSQL_AUTH_H */
