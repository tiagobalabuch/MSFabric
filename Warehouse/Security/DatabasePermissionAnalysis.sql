/*
----------------------------------------------------------------------------------------------------
Script: Database Permission Analysis

Author: Tiago Balabuch
Date Created: 12-03-2025
Last Modified: 12-03-2025 
Version: 1.0 
Environment: Microsoft Fabric Warehouse

Purpose:
    This script retrieves and combines both explicit and implicit database permissions
    for specified principals within the current database.

Description:
    - ExplicitPermissions CTE:
        Identifies permissions directly granted to database principals.
        It extracts information like principal name, permission type, action,
        securable object, and column-level permissions.

    - ImplicitPermissions CTE:
        Determines permissions inherited through membership in database roles,
        especially fixed database roles (FDR).
        It identifies role membership and maps it to corresponding permissions.
        "IMPLICIT - FDR" in the Action column indicates permissions granted via
        membership in a standard, built-in database role.

    The final SELECT statement merges the results of both CTEs, groups the data,
    and formats it for easy analysis. 
    Column level permissions are aggregated using STRING_AGG.

    The output is ordered by DatabasePrincipal and Securable for better readability.

Usage:
    - Ensure the user executing this script has sufficient permissions to query 
    system views.

Output Columns:
    - DatabasePrincipal: The name of the database principal.
    - PermissionType: 'explicit' or 'implicit'.
    - PermissionDerivedFrom: The role from which implicit permissions are derived (NULL for explicit).
    - PrincipalType: The type of database principal (e.g., SQL_USER, SQL_ROLE).
    - Authentication: The authentication type (e.g., EXTERNAL, SQL).
    - Action: The permission action (e.g., GRANT, DENY, IMPLICIT - Fixed Database Role (FDR)).
    - Permission: The permission name or description.
    - ObjectType: The type of securable object (e.g., USER_TABLE, DATABASE).
    - Securable: The securable object (e.g., Database::[DatabaseName], Object::[Schema].[TableName]).
    - ColumnName: The column name (if applicable) or 'ALL COLUMNS'.

**DISCLAIMER:**
    This script is provided "as is" without any support or guarantee. The user assumes
    all responsibility for its use. It is recommended to thoroughly test and understand
    the script's behavior in a non-production environment before applying it to a
    production system. The author(s) and provider(s) of this script shall not be held
    liable for any damages or losses resulting from its use.

----------------------------------------------------------------------------------------------------
*/
DECLARE @principalName sysname = 'Dummy';

WITH ExplicitPermissions AS (
    SELECT
        dbpr.name AS DatabasePrincipal,
        '<explicit>' AS PermissionType,
        NULL AS PermissionDerivedFrom,
        dbpr.type_desc AS PrincipalType,
        dbpr.authentication_type_desc AS Authentication,
        perm.state_desc AS Action,
        perm.permission_name AS Permission,
        obj.type_desc AS ObjectType,
        CASE perm.class
            WHEN 0 THEN 'Database::' + DB_NAME()
            WHEN 1 THEN 'Object::' + SCHEMA_NAME(obj.schema_id) + '.' + COALESCE(OBJECT_NAME(perm.major_id), '<UNKNOWN OBJECT>')
            WHEN 3 THEN 'Schema::' + COALESCE(SCHEMA_NAME(perm.major_id), '<UNKNOWN SCHEMA>')
        END AS Securable,
        CASE
            WHEN perm.class = 1 AND obj.type = 'U' THEN COALESCE(col.name, 'ALL COLUMNS')
            ELSE NULL
        END AS ColumnName
    FROM
        sys.database_permissions AS perm
    INNER JOIN
        sys.database_principals AS dbpr ON perm.grantee_principal_id = dbpr.principal_id
    LEFT JOIN
        sys.objects AS obj ON perm.major_id = obj.object_id AND obj.is_ms_shipped = 0
    LEFT JOIN
        sys.columns AS col ON perm.major_id = col.object_id AND perm.minor_id = col.column_id
    WHERE (@principalName IS NULL OR dbpr.name = @principalName)
),
ImplicitPermissions AS (
    SELECT
        princ_mem.name AS DatabasePrincipal,
        '<implicit>' AS PermissionType,
        princ_role.name AS PermissionDerivedFrom,
        princ_mem.type_desc AS PrincipalType,
        princ_mem.authentication_type_desc AS Authentication,
        CASE
            WHEN princ_role.name IN (
                'db_owner',
                'db_ddladmin',
                'db_datareader',
                'db_datawriter',
                'db_securityadmin',
                'db_accessadmin',
                'db_backupoperator',
                'db_denydatawriter',
                'db_denydatareader'
            ) THEN 'IMPLICIT - FDR'
            ELSE pe.state_desc
        END AS Action,
        CASE princ_role.name
            WHEN 'db_owner' THEN 'CONTROL'
            WHEN 'db_ddladmin' THEN 'CREATE, DROP, ALTER ON ANY OBJECTS'
            WHEN 'db_datareader' THEN 'SELECT'
            WHEN 'db_datawriter' THEN 'INSERT, UPDATE, DELETE'
            WHEN 'db_securityadmin' THEN 'Manage Role Membership and Permissions'
            WHEN 'db_accessadmin' THEN 'GRANT/REVOKE access to users/roles'
            WHEN 'db_backupoperator' THEN 'Can BACKUP DATABASE'
            WHEN 'db_denydatawriter' THEN 'DENY INSERT, UPDATE, DELETE'
            WHEN 'db_denydatareader' THEN 'DENY SELECT'
            ELSE pe.permission_name
        END AS Permission,
        obj.type_desc AS ObjectType,
        COALESCE(
            CASE pe.class
                WHEN 0 THEN 'Database::' + DB_NAME()
                WHEN 1 THEN 'Object::' + SCHEMA_NAME(obj.schema_id) + '.' + COALESCE(OBJECT_NAME(pe.major_id), '<UNKNOWN_OBJECT>')
                WHEN 3 THEN 'Schema::' + COALESCE(SCHEMA_NAME(pe.major_id), '<UNKNOWN_SCHEMA>')
            END,
            'Database::' + DB_NAME()
        ) AS Securable,
        CASE
            WHEN pe.class = 1 AND obj.type = 'U' THEN COALESCE(col.name, 'ALL COLUMNS')
            ELSE NULL
        END AS ColumnName
    FROM
        sys.database_role_members AS dbrm
    RIGHT OUTER JOIN
        sys.database_principals AS princ_role ON dbrm.role_principal_id = princ_role.principal_id
    LEFT OUTER JOIN
        sys.database_principals AS princ_mem ON dbrm.member_principal_id = princ_mem.principal_id
    LEFT JOIN
        sys.database_permissions AS pe ON pe.grantee_principal_id = princ_role.principal_id
    LEFT JOIN
        sys.objects AS obj ON pe.major_id = obj.object_id AND obj.is_ms_shipped = 0
    LEFT JOIN
        sys.columns AS col ON pe.major_id = col.object_id AND pe.minor_id = col.column_id
    WHERE
        princ_role.type = 'R'
        AND princ_mem.name IS NOT NULL
        AND (@principalName IS NULL OR princ_role.name = @principalName)
)
SELECT
    DatabasePrincipal,
    PermissionType,
    PermissionDerivedFrom,
    PrincipalType,
    Authentication,
    Action,
    Permission,
    ObjectType,
    Securable,
    COALESCE(STRING_AGG(ColumnName, ', '), NULL) AS ColumnName
FROM
    (
        SELECT *
        FROM ExplicitPermissions
        UNION ALL
        SELECT *
        FROM ImplicitPermissions
    ) AS CombinedPermissions
GROUP BY
    DatabasePrincipal,
    PermissionType,
    PermissionDerivedFrom,
    PrincipalType,
    Authentication,
    Action,
    Permission,
    ObjectType,
    Securable
ORDER BY
    DatabasePrincipal,
    Securable;