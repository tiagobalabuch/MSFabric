/*
----------------------------------------------------------------------------------------------------
Script: Table Statistics Analysis

Author: Tiago Balabuch
Date Created: 14/03/2025
Last Modified: 14/03/2025
Version: 1.0 
Environment: Microsoft Fabric Warehouse

Purpose:
    This script retrieves and analyzes statistics information for user tables
    within the current database.

Description:
    The script queries system views to gather details about table statistics,
    including their names, associated columns, creation types, update settings,
    and filter definitions.

    It provides insights into:
    - Which tables have statistics.
    - The columns included in each statistic.
    - Whether the statistics were auto-created 
    - If the statistics were user-created or system-generated.
    - Whether automatic updates are enabled or disabled.
    - If filters are applied to the statistics.
    - The filter definitions (if any).
    - The type of statistics (temporary or persistent).
    - The generation method of the statistic.

    The output is ordered by table name for better readability.

Usage:
    - This script can be run against any database to analyze table statistics.
    - It excludes system and internal tables.
    - The script relies on system views (sys.stats, sys.objects, sys.stats_columns, sys.columns).
    - Ensure the user executing this script has sufficient permissions to query these system views.
    - This script is designed for informational purposes.

Output Columns:
    - SchemaName: The schema name of the table.
    - TableName: The name of the table.
    - StatisticsName: The name of the statistics object.
    - StatsColumns: A comma-separated list of columns included in the statistics.
    - AutoCreated: Indicates if the statistics were auto-created by Fabric Warehouse
    - UserCreated: Indicates if the statistics were created by a user.
    - AutoUpdate: Indicates if automatic statistics updates are enabled.
    - FilterApplied: Indicates if a filter is applied to the statistics.
    - FilterDefinition: The filter definition (if applicable).
    - StatisticsType: Indicates if the statistics are temporary or persistent.
    - GenerationMethod: The method used to generate the statistics.

Example:
    This script can be used to identify statistics that may need manual updates or
    to verify that automatic updates are enabled. It is also useful in understanding
    the statistics created by the Fabric Warehouse.

**DISCLAIMER:**
    This script is provided "as is" without any support or guarantee. The user assumes
    all responsibility for its use. It is recommended to thoroughly test and understand
    the script's behavior in a non-production environment before applying it to a
    production system. The author(s) and provider(s) of this script shall not be held
    liable for any damages or losses resulting from its use.

    This script should be used for informational and auditing purposes only. Do not
    directly implement statistics changes based solely on this script's output without
    proper validation and testing.

    Always consult your database administrator or performance tuning specialist for guidance on
    statistics management and performance best practices.

----------------------------------------------------------------------------------------------------
*/

SELECT
    DB_NAME() as DatabaseName,
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    OBJECT_NAME(s.object_id) AS TableName,
    s.name AS StatisticsName,
    (
        SELECT STRING_AGG(cols.name, ', ') WITHIN GROUP (ORDER BY statcols.stats_column_id)
        FROM sys.stats_columns AS statcols
        JOIN sys.columns AS cols
            ON statcols.column_id = cols.column_id
            AND statcols.object_id = cols.object_id
        WHERE statcols.stats_id = s.stats_id
            AND statcols.object_id = s.object_id
    ) AS StatsColumns,
    CASE
        WHEN s.auto_created = 1 THEN 'Auto-created'
        ELSE 'Not auto-created'
    END AS AutoCreated,
    CASE
        WHEN s.user_created = 1 THEN 'Created by a user'
        ELSE 'System-generated'
    END AS UserCreated,
    CASE
        WHEN s.no_recompute = 1 THEN 'Recompute disabled'
        ELSE 'Recompute enabled'
    END AS AutoUpdate,
    CASE
        WHEN s.has_filter = 1 THEN 'Filtered statistics applied'
        ELSE 'Full dataset statistics'
    END AS FilterApplied,
    s.filter_definition AS FilterDefinition,
    CASE
        WHEN s.is_temporary = 1 THEN 'Temporary statistics'
        ELSE 'Persistent statistics'
    END AS StatisticsType,
    s.stats_generation_method_desc AS GenerationMethod
FROM sys.stats AS s
INNER JOIN sys.objects AS o
    ON s.object_id = o.object_id
WHERE o.type_desc NOT IN (N'SYSTEM_TABLE', N'INTERNAL_TABLE')
ORDER BY SchemaName, TableName;