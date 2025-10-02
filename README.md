# Oracle Partition Handler

## Overview

The Oracle Partition Handler is an enterprise-grade PL/SQL framework designed to automate the management of table and index partitions in Oracle databases. It provides a configuration-driven approach to handle complex partition lifecycle operations including creation, splitting, merging, moving, dropping, and online redefinition of partitioned objects.

**Version**: 0.9.45  
**Author**: Thomas Krahn  
**Requirements**: Oracle Database 11g or higher

---

## Table of Contents

1. [Core Features](#core-features)
2. [Oracle 19c Features](#oracle-19c-features) ⭐
3. [Architecture](#architecture)
4. [Database Schema](#database-schema)
5. [Core Packages](#core-packages)
6. [Installation](#installation)
7. [Configuration](#configuration)
8. [Usage Examples](#usage-examples)
9. [Extension & Enhancement Guide](#extension--enhancement-guide)
10. [Key Design Patterns](#key-design-patterns)
11. [Troubleshooting](#troubleshooting)

---

## Core Features

### Automated Partition Management
- **Automatic Partition Creation**: Creates new partitions based on predefined configurations
- **Auto-Adjust Feature**: Dynamically adjusts partition boundaries based on calculated functions
- **Moving Window**: Maintains a rolling window of partitions, automatically dropping old partitions
- **Online Redefinition**: Converts non-partitioned or improperly partitioned tables to correct partition schemes without downtime

### Supported Partition Types
- **RANGE Partitioning**: Time-based or numeric range partitions
- **LIST Partitioning**: Discrete value-based partitions  
- **HASH Partitioning**: Even data distribution across partitions
- **INTERVAL Partitioning**: Automatic partition creation for range partitions
- **REFERENCE Partitioning**: Parent-child relationship partitioning
- **AUTO_LIST Partitioning** ⭐ **(Oracle 19c)**: Automatic LIST partition creation for new values
- **Composite Partitioning**: Partition + Subpartition combinations
  - Traditional: RANGE-RANGE, RANGE-HASH, RANGE-LIST, LIST-RANGE, LIST-HASH, LIST-LIST
  - **Oracle 19c** ⭐: HASH-RANGE, HASH-HASH, HASH-LIST

### Advanced Operations
- **Partition Split**: Splits existing partitions when boundaries change
- **Partition Merge**: Consolidates multiple partitions
- **Partition Move**: Relocates partitions to different tablespaces
- **Partition Drop**: Removes obsolete partitions
- **Partition Rename**: Renames partitions to match naming conventions
- **Index Synchronization**: Keeps local and global indexes synchronized with partition operations

---

## Oracle 19c Features

**New Package**: `PARTITION_REDEFINE_19C` provides modern partition conversion capabilities specifically designed for Oracle 19c.

### Key 19c Enhancements

#### AUTO_LIST Partitioning
- **Automatic partition creation** for new LIST values
- No need to pre-define all partitions
- Ideal for evolving categorical data
- **Technique ID**: 6

#### HASH-Based Composite Partitioning
Oracle 19c introduces HASH as a primary partition method in composite partitioning:
- **HASH-RANGE**: Even distribution + time-based subdivision
- **HASH-HASH**: Maximum parallel processing capability
- **HASH-LIST**: Load balancing + categorical subdivision

#### Modern Conversion Operations

1. **convert_to_single_level_partition**: Convert regular table to single-level partitioning
2. **convert_to_composite_partition**: Convert regular table to composite partitioning
3. **convert_single_to_composite**: Convert single-level to composite partitioning

#### Online vs Offline Conversion
- Automatic detection of online conversion capability
- Minimal downtime with incremental sync
- Table copy with rename and sync mechanism
- Atomic switchover (table → table_OLD, table_NEW → table)

#### Advanced Features
- Parallel processing support
- Constraint management (disable/enable)
- Index copying with _NEW suffix cleanup
- Status monitoring and sync loops
- Comprehensive error handling and logging

**📖 Full Documentation**: See [README_19C.md](README_19C.md) for complete guide with examples

---

## Architecture

### High-Level Design

```
┌─────────────────────────────────────────────────────────────┐
│                    PARTITION HANDLER                        │
│                   (Main Orchestrator)                       │
│  - Loads object definitions from configuration              │
│  - Coordinates partition operations                         │
│  - Handles exceptions and logging                           │
└────────────┬────────────────────────────────────────────────┘
             │
             ├──> PARTITION_CONFIG (Configuration Management)
             │    - Add/remove tables and indexes
             │    - Define partition keys and definitions
             │    - Enable/disable partition handling
             │
             ├──> PARTITION_TOOLS (Utility Functions)
             │    - Data type conversions
             │    - Literal format handling
             │    - Timestamp conversions
             │
             ├──> PARTITION_REDEFINE (Online Redefinition)
             │    - Table redefinition using DBMS_REDEFINITION
             │    - Constraint and index copying
             │    - Dependency management
             │
             └──> PARTITION_TYPES (Type Definitions)
                  - Custom types and records
                  - Collection types
                  - Shared type definitions
```

### Processing Flow

1. **Initialization**: Load configuration, set session parameters, initialize dependencies
2. **Load Object Definitions**: Query enabled partitioned objects from `PARTITION_OBJECT` view
3. **For Each Object**:
   - Load partition definitions from `P_DEF` table
   - Check if object needs redefinition (structure mismatch)
   - If redefinition needed: Use `PARTITION_REDEFINE` package
   - If partitions need adjustment: Process each partition definition
4. **Partition Operations**:
   - Compare configured partitions vs. actual partitions
   - Determine required actions (ADD, SPLIT, MERGE, DROP, MOVE, RENAME)
   - Execute DDL statements with proper error handling
   - Update global indexes if needed
5. **Finalization**: Rebuild unusable indexes, log completion, update run timestamps

---

## Database Schema

### Core Tables

#### P_OTYPE (Object Types)
Defines the types of objects that can be partitioned.
```sql
ID          NUMBER(38)     -- Primary Key
NAME        VARCHAR2(30)   -- TABLE or INDEX  
DESCRIPTION VARCHAR2(255)  -- Description
```

#### P_OBJ (Partitioned Objects)
Registry of tables and indexes to be managed.
```sql
ID                  NUMBER(38)     -- Primary Key (from P_OBJ_ID_SEQ)
P_OTYPE_ID          NUMBER(38)     -- FK to P_OTYPE (1=TABLE, 2=INDEX)
OWNER               VARCHAR2(30)   -- Schema owner
NAME                VARCHAR2(30)   -- Object name
ENABLED             NUMBER(1)      -- 0=Disabled, 1=Enabled
ORDER#              NUMBER(19)     -- Processing order (NULL = no preference)
LAST_RUN_START_TS   TIMESTAMP      -- Last execution start
LAST_RUN_END_TS     TIMESTAMP      -- Last execution end
LAST_RUN_DURATION   INTERVAL       -- Calculated duration
```

#### P_PTYPE (Partition Types)
Defines partition levels (partition vs subpartition).
```sql
ID          NUMBER(38)     -- 1=PARTITION, 2=SUBPARTITION
NAME        VARCHAR2(30)   
DESCRIPTION VARCHAR2(255)
```

#### P_TECH (Partition Techniques)
Available partitioning techniques.
```sql
ID          NUMBER(38)     -- 1=LIST, 2=RANGE, 3=HASH, 4=INTERVAL, 5=REFERENCE
NAME        VARCHAR2(10)   
DESCRIPTION VARCHAR2(255)
```

#### P_KEY (Partition Keys)
Defines partition key columns for each object.
```sql
P_OBJ_ID    NUMBER(38)     -- FK to P_OBJ
P_PTYPE_ID  NUMBER(38)     -- FK to P_PTYPE (partition or subpartition level)
P_TECH_ID   NUMBER(38)     -- FK to P_TECH (partitioning technique)
COLUMN_NAME VARCHAR2(30)   -- Column used for partitioning
ENABLED     NUMBER(1)      -- 0=Disabled, 1=Enabled
```

#### P_DEF (Partition Definitions)
Detailed configuration for each partition or subpartition.
```sql
P_OBJ_ID                 NUMBER(38)      -- FK to P_OBJ
PARTITION#               NUMBER(7)       -- Partition order number (1-1048575)
SUBPARTITION#            NUMBER(7)       -- Subpartition number (0 for partitions)
ENABLED                  NUMBER(1)       -- Enable/disable this definition
HIGH_VALUE               VARCHAR2(255)   -- Partition boundary value
HIGH_VALUE_FORMAT        VARCHAR2(30)    -- Date/timestamp format string
P_NAME                   VARCHAR2(30)    -- Partition name (or format template)
P_NAME_PREFIX            VARCHAR2(30)    -- Prefix for auto-generated names
P_NAME_SUFFIX            VARCHAR2(30)    -- Suffix for auto-generated names
P_NAMING_FUNCTION        VARCHAR2(30)    -- Function for name generation
TBS_NAME                 VARCHAR2(30)    -- Tablespace name (or format template)
TBS_NAME_PREFIX          VARCHAR2(30)    -- Tablespace prefix
TBS_NAME_SUFFIX          VARCHAR2(30)    -- Tablespace suffix
TBS_NAMING_FUNCTION      VARCHAR2(30)    -- Function for tablespace name
AUTO_ADJUST_ENABLED      NUMBER(1)       -- Enable auto-adjustment
AUTO_ADJUST_FUNCTION     VARCHAR2(30)    -- Function for calculating new boundaries
AUTO_ADJUST_VALUE        VARCHAR2(30)    -- Parameter for adjust function
AUTO_ADJUST_END          VARCHAR2(255)   -- Number of future partitions
AUTO_ADJUST_START        VARCHAR2(255)   -- Number of past partitions
MOVING_WINDOW            NUMBER(1)       -- 0=Off, 1=Drop old, 2=Merge old
MOVING_WINDOW_FUNCTION   VARCHAR2(255)   -- Function to determine retention
```

#### P_OBJ_LOG (Audit Log)
Tracks changes to partition configurations.
```sql
ID              NUMBER(38)     -- Primary Key
P_OBJ_ID        NUMBER(38)     -- FK to P_OBJ
ACTION          VARCHAR2(30)   -- Type of action performed
TIMESTAMP       TIMESTAMP      -- When action occurred
USER_ID         VARCHAR2(30)   -- User who performed action
DETAILS         VARCHAR2(4000) -- Additional details
```

### Views

#### PARTITION_OBJECT
Consolidated view combining object definitions with partition key metadata.
```sql
SELECT o.id AS object_id,
       o.enabled,
       o.order#,
       ot.name AS object_type,
       o.owner AS object_owner,
       o.name AS object_name,
       pk.column_name AS partition_key,
       -- ... data types and techniques
FROM p_obj o
JOIN p_otype ot ON ot.id = o.p_otype_id
JOIN p_key pk ON pk.p_obj_id = o.id
```

---

## Core Packages

### 1. PARTITION_HANDLER (Main Package)
**File**: `partition_handler.pck`  
**Version**: 0.9.45

**Purpose**: Central orchestrator for all partition management operations.

**Key Procedures/Functions**:
- `handle_partitions()` - Main entry point, processes all enabled objects
- `handle_object()` - Processes a single table or index
- `handle_object_partitions()` - Manages partition definitions for an object
- `handle_existing_partitions()` - Cleans up extra or misnamed partitions
- `add_partition()` - Creates new partitions
- `split_partition()` - Splits a partition at a new boundary
- `merge_partitions()` - Merges consecutive partitions
- `drop_partition()` - Removes a partition
- `move_partition()` - Relocates partition to different tablespace
- `rename_partition()` - Renames partition to match configuration

**Key Cursors**:
- `cur_obj_defs` - Loads enabled objects ordered by type and order#
- `cur_part_defs` - Loads partition definitions with all metadata

**Configuration Constants**:
- `c_default_parallel_degree` = 4
- `c_default_ddl_lock_timeout` = 300 seconds

**Process Actions** (return codes):
```plsql
c_pa_not_found   = 0  -- Partition doesn't exist
c_pa_found       = 1  -- Partition exists and matches
c_pa_renamed     = 3  -- Partition was renamed
c_pa_must_add    = 4  -- Need to create partition
c_pa_added       = 5  -- Partition created
c_pa_must_split  = 6  -- Need to split partition
c_pa_splitted    = 7  -- Partition split
c_pa_must_merge  = 8  -- Need to merge partitions
c_pa_merged      = 9  -- Partitions merged
c_pa_moved       = 11 -- Partition moved
c_pa_must_drop   = 12 -- Need to drop partition
c_pa_dropped     = 13 -- Partition dropped
```

### 2. PARTITION_CONFIG (Configuration Management)
**File**: `partition_config.pck`  
**Version**: 0.9.4

**Purpose**: Provides API for configuring partitioned objects and their definitions.

**Key Procedures**:

**Object Management**:
- `add_table(owner, table_name, enabled, order#)` - Register a table
- `del_table(owner, table_name)` - Unregister a table
- `add_index(owner, index_name, enabled, order#)` - Register an index
- `del_index(owner, index_name)` - Unregister an index
- `enable_table(owner, table_name)` - Enable partition handling
- `disable_table(owner, table_name)` - Disable partition handling
- `enable_index(owner, index_name)` - Enable index partition handling
- `disable_index(owner, index_name)` - Disable index partition handling

**Partition Key Configuration**:
- `add_table_partition_key(owner, table_name, column_name, technique_id, enabled)`
- `add_table_subpartition_key(owner, table_name, column_name, technique_id, enabled)`
- `add_index_partition_key(owner, index_name, column_name, technique_id, enabled)`
- `add_index_subpartition_key(owner, index_name, column_name, technique_id, enabled)`

**Partition Definition Management**:
- `add_table_partition(...)` - Define a table partition (17 parameters)
- `add_table_subpartition(...)` - Define a table subpartition
- `add_index_partition(...)` - Define an index partition
- `add_index_subpartition(...)` - Define an index subpartition
- `update_table_high_value()` - Modify partition boundary
- `update_index_high_value()` - Modify index partition boundary

### 3. PARTITION_REDEFINE (Online Redefinition)
**File**: `partition_redefine.pck`  
**Version**: 0.9.18

**Purpose**: Handles online redefinition of tables when partition structure doesn't match configuration.

**Key Procedures**:
- `redefine_object(obj_def, part_defs)` - Main entry point
- `redefine_table(owner, table_name, interim_table, option)` - Executes DBMS_REDEFINITION
- `table_can_be_redefined(owner, table_name)` - Checks if redefinition is possible
- `get_constraint_ddls(owner, table_name)` - Extracts constraint definitions
- `get_index_ddls(owner, table_name)` - Extracts index definitions

**Redefinition Options**:
```plsql
DBMS_REDEFINITION.CONS_USE_ROWID  -- For tables without PK
DBMS_REDEFINITION.CONS_USE_PK     -- For tables with PK
```

**Process Flow**:
1. Validate redefinition is possible
2. Create temporary interim table with correct partition structure
3. Start redefinition via `DBMS_REDEFINITION.START_REDEF_TABLE`
4. Sync data with `SYNC_INTERIM_TABLE`
5. Copy dependent objects (indexes, constraints, triggers, privileges)
6. Finish redefinition
7. Clean up temporary objects

### 3a. PARTITION_REDEFINE_19C (Oracle 19c Enhanced Conversion) ⭐
**File**: `partition_redefine_19c.pck`  
**Version**: 1.0.0

**Purpose**: Modern partition conversion utilities specifically for Oracle 19c, supporting new partition techniques and advanced conversion strategies.

**Key Features**:
- Support for AUTO_LIST partitioning (Oracle 19c)
- Support for HASH-based composite partitioning (HASH-RANGE, HASH-HASH, HASH-LIST)
- Online and offline conversion strategies
- Incremental sync with table rename mechanism
- Automatic online capability detection
- Parallel processing support

**Key Functions**:
- `convert_to_single_level_partition()` - Convert regular table to single-level partitioning
- `convert_to_composite_partition()` - Convert regular table to composite partitioning
- `convert_single_to_composite()` - Convert single-level to composite partitioning
- `is_online_conversion_capable()` - Check if online conversion is possible
- `generate_partition_ddl_19c()` - Generate Oracle 19c partition DDL

**Key Procedures**:
- `execute_conversion_with_sync()` - Full conversion workflow with sync and rename
- `cleanup_object_names()` - Rename indexes/constraints from _NEW to original names

**Conversion Workflow**:
1. Create new table with `_NEW` suffix
2. Copy constraints (disabled) and indexes
3. Initial data load (INSERT INTO SELECT)
4. Incremental sync loop (for online strategy)
5. Enable and validate constraints
6. Atomic rename (original → `_OLD`, `_NEW` → original)
7. Optional cleanup of object names

**📖 See [README_19C.md](README_19C.md) for complete documentation and examples**

### 4. PARTITION_TOOLS (Utility Functions)
**File**: `partition_tools.pck`  
**Version**: 0.9.9

**Purpose**: Utility functions for data conversions and formatting.

**Key Procedures**:
- `convert_literal_to_varchar2(literal, v2_out)` - Convert to VARCHAR2
- `convert_literal_to_number(literal, n_out)` - Convert to NUMBER
- `convert_ts_wltz_to_literal(timestamp, literal_out)` - Timestamp to string
- `convert_lf_tab_to_ts_hv_tab(literal_format_tab, ts_tab_out)` - Batch conversion
- `convert_v2_to_v2_tab(v2_string, v2_tab_out)` - Parse CSV string to table

**Purpose**: These utilities handle the complex conversions between partition boundary literals (stored as VARCHAR2 in data dictionary) and actual typed values (DATE, TIMESTAMP, NUMBER).

### 5. PARTITION_TYPES (Type Definitions)
**File**: `partition_types.spc`  
**Version**: 0.9.25

**Purpose**: Centralized type definitions used across all packages.

**Key Types**:

**Record Types**:
```plsql
TYPE t_partition_def IS RECORD (
    partition_type_id           t_partition_type_id,
    partition_tech_id           t_partition_technique_id,
    partition_technique         t_partition_technique_name,
    p_obj_id                    t_object_id,
    partition#                  t_partition_number,
    subpartition#               t_subpartition_number,
    data_type                   VARCHAR2(106 CHAR),
    partition_name              t_partition_name,
    tablespace_name             t_tablespace_name,
    high_value                  t_high_value,
    high_value_ts_tz            t_high_value_ts_tz,
    auto_adjust_enabled         t_auto_adjust_enabled,
    moving_window               t_moving_window,
    -- ... 30+ fields total
);

TYPE t_partition_info IS RECORD (
    partition_type              t_partition_type_name,
    partition_name              dba_tab_partitions.partition_name%TYPE,
    subpartition_name           dba_tab_subpartitions.subpartition_name%TYPE,
    tablespace_name             dba_tab_partitions.tablespace_name%TYPE,
    high_value                  dba_tab_partitions.high_value%TYPE,
    high_value_ts_tz            t_high_value_ts_tz,
    subpartition_count          NUMBER,
    label_name                  VARCHAR2(74 CHAR)
);
```

**Collection Types**:
```plsql
TYPE t_object_table IS TABLE OF partition_object%ROWTYPE INDEX BY BINARY_INTEGER;
TYPE t_partition_def_table IS TABLE OF t_partition_def INDEX BY BINARY_INTEGER;
TYPE t_partition_info_table IS TABLE OF t_partition_info INDEX BY BINARY_INTEGER;
TYPE t_literal_format_tab IS TABLE OF t_literal_format INDEX BY BINARY_INTEGER;
TYPE t_varchar2_tab IS TABLE OF long_varchar INDEX BY BINARY_INTEGER;
```

### 6. PARTITION_CONSTANTS (System Constants)
**File**: `partition_constants.spc`  
**Version**: 0.9.17

**Purpose**: Centralized constant definitions for partition handler.

**Categories**:
- **Enable/Disable**: `c_enabled = 1`, `c_disabled = 0`
- **Object Types**: `c_obj_type_table_id = 1`, `c_obj_type_index_id = 2`
- **Partition Types**: `c_par_type_partition_id = 1`, `c_par_type_subpartition_id = 2`
- **Techniques**: `c_par_tech_list_id = 1`, `c_par_tech_range_id = 2`, etc.
- **Data Types**: All supported Oracle data types as constants
- **SQL Keywords**: `c_maxvalue`, `c_default`, `c_to_date`, etc.

---

## Installation

### Prerequisites

1. **Oracle Database**: Version 11g or higher
2. **Required Dependencies**:
   - `log_admin` package (v1.2.3+) - Logging framework
   - `module_admin` package (v0.7.1+) - Module configuration
   - `sql_admin` package - SQL execution utilities
   - `object_admin` package - Object management utilities

3. **Privileges Required**:
   ```sql
   GRANT CREATE TABLE TO <schema>;
   GRANT CREATE SEQUENCE TO <schema>;
   GRANT CREATE VIEW TO <schema>;
   GRANT CREATE PROCEDURE TO <schema>;
   GRANT SELECT ON DBA_TABLES TO <schema>;
   GRANT SELECT ON DBA_TAB_PARTITIONS TO <schema>;
   GRANT SELECT ON DBA_TAB_SUBPARTITIONS TO <schema>;
   GRANT SELECT ON DBA_INDEXES TO <schema>;
   GRANT SELECT ON DBA_IND_PARTITIONS TO <schema>;
   GRANT SELECT ON DBA_IND_SUBPARTITIONS TO <schema>;
   GRANT SELECT ON DBA_TAB_COLUMNS TO <schema>;
   GRANT SELECT ON DBA_IND_COLUMNS TO <schema>;
   GRANT SELECT ON DBA_CONSTRAINTS TO <schema>;
   GRANT EXECUTE ON DBMS_REDEFINITION TO <schema>;
   GRANT ALTER SESSION TO <schema>;
   ```

### Installation Steps

1. **Set Tablespace Variables**:
   ```sql
   DEFINE DATA_TBS = 'USERS'
   DEFINE INDEX_TBS = 'USERS'
   ```

2. **Run Installation Script**:
   ```sql
   @install.sql
   ```

   This script installs components in the following order:
   - `partition_constants.spc` - Constants
   - `partition_types.spc` - Type definitions
   - `p_tech.sql` - Partition technique lookup
   - `p_ptype.sql` - Partition type lookup
   - `p_otype.sql` - Object type lookup
   - `p_obj.sql` - Object registry table
   - `p_obj_log.sql` - Audit log table
   - `p_key.sql` - Partition key definitions
   - `p_def.sql` - Partition definitions
   - `partition_object.sql` - Consolidated view
   - `partition_config.pck` - Configuration API
   - `partition_tools.pck` - Utility functions
   - `partition_redefine.pck` - Redefinition logic
   - `partition_handler.pck` - Main handler
   - `context.sql` - Application context (optional)

3. **Verify Installation**:
   ```sql
   SELECT object_name, object_type, status 
   FROM user_objects 
   WHERE object_name LIKE 'PARTITION%' OR object_name LIKE 'P_%'
   ORDER BY object_type, object_name;
   ```

   All objects should have STATUS = 'VALID'.

---

## Configuration

### Basic Workflow

1. **Register a Table**
2. **Define Partition Key**
3. **Define Partition Definitions**
4. **Enable the Table**
5. **Run Partition Handler**

### Example: Configure Monthly Range Partitioning

```sql
BEGIN
    -- Step 1: Register the table
    partition_config.add_table(
        owner_in      => 'MYSCHEMA',
        table_name_in => 'SALES_DATA',
        enabled_in    => 0,  -- Start disabled
        order#_in     => 10  -- Process priority
    );
    
    -- Step 2: Define partition key (RANGE on SALE_DATE)
    partition_config.add_table_partition_key(
        owner_in        => 'MYSCHEMA',
        table_name_in   => 'SALES_DATA',
        column_name_in  => 'SALE_DATE',
        technique_id_in => partition_constants.c_par_tech_range_id,
        enabled_in      => partition_constants.c_enabled
    );
    
    -- Step 3a: Define first partition (January 2024)
    partition_config.add_table_partition(
        owner_in             => 'MYSCHEMA',
        table_name_in        => 'SALES_DATA',
        partition#_in        => 1,
        high_value_in        => '2024-02-01',
        high_value_format_in => 'YYYY-MM-DD',
        p_name_in            => 'SALES_202401',
        tbs_name_in          => 'DATA_2024',
        enabled_in           => 1
    );
    
    -- Step 3b: Define additional partitions...
    partition_config.add_table_partition(
        owner_in             => 'MYSCHEMA',
        table_name_in        => 'SALES_DATA',
        partition#_in        => 2,
        high_value_in        => '2024-03-01',
        high_value_format_in => 'YYYY-MM-DD',
        p_name_in            => 'SALES_202402',
        tbs_name_in          => 'DATA_2024',
        enabled_in           => 1
    );
    
    -- Step 4: Enable partition handling
    partition_config.enable_table(
        owner_in      => 'MYSCHEMA',
        table_name_in => 'SALES_DATA'
    );
    
    COMMIT;
END;
/
```

### Advanced Configuration: Auto-Adjust Feature

Auto-adjust automatically creates future partitions and manages past partitions.

```sql
BEGIN
    partition_config.add_table_partition(
        owner_in                 => 'MYSCHEMA',
        table_name_in            => 'SALES_DATA',
        partition#_in            => 1,
        high_value_in            => 'YYYY-MM-DD',  -- Format template
        high_value_format_in     => 'YYYY-MM-DD',
        p_name_in                => 'SALES_YYYYMM',  -- Name template
        p_naming_function_in     => 'TO_CHAR',
        tbs_name_in              => 'DATA_YYYY',     -- Tablespace template
        tbs_naming_function_in   => 'TO_CHAR',
        auto_adjust_enabled_in   => 1,
        auto_adjust_function_in  => 'ADD_MONTHS',    -- Increment function
        auto_adjust_value_in     => '1',             -- Add 1 month
        auto_adjust_start_in     => '3',             -- Keep 3 past partitions
        auto_adjust_end_in       => '6',             -- Create 6 future partitions
        moving_window_in         => 1,               -- Drop old partitions
        enabled_in               => 1
    );
END;
/
```

**How Auto-Adjust Works**:
1. Calculates the "current" period based on SYSDATE
2. Creates `auto_adjust_end` (6) partitions into the future
3. Maintains `auto_adjust_start` (3) partitions in the past
4. When `moving_window = 1`, drops partitions older than the start window
5. When `moving_window = 2`, merges old partitions instead of dropping

### Composite Partitioning (Partition + Subpartition)

```sql
BEGIN
    -- Define main partition key
    partition_config.add_table_partition_key(
        owner_in        => 'MYSCHEMA',
        table_name_in   => 'ORDERS',
        column_name_in  => 'ORDER_DATE',
        technique_id_in => partition_constants.c_par_tech_range_id
    );
    
    -- Define subpartition key
    partition_config.add_table_subpartition_key(
        owner_in        => 'MYSCHEMA',
        table_name_in   => 'ORDERS',
        column_name_in  => 'REGION_CODE',
        technique_id_in => partition_constants.c_par_tech_list_id
    );
    
    -- Define partition (Q1 2024)
    partition_config.add_table_partition(
        owner_in             => 'MYSCHEMA',
        table_name_in        => 'ORDERS',
        partition#_in        => 1,
        high_value_in        => '2024-04-01',
        high_value_format_in => 'YYYY-MM-DD',
        p_name_in            => 'ORDERS_2024Q1',
        tbs_name_in          => 'DATA_2024',
        enabled_in           => 1
    );
    
    -- Define subpartitions within partition 1
    partition_config.add_table_subpartition(
        owner_in             => 'MYSCHEMA',
        table_name_in        => 'ORDERS',
        partition#_in        => 1,
        subpartition#_in     => 1,
        high_value_in        => 'NORTH',
        p_name_in            => 'ORDERS_2024Q1_NORTH',
        tbs_name_in          => 'DATA_2024',
        enabled_in           => 1
    );
    
    partition_config.add_table_subpartition(
        owner_in             => 'MYSCHEMA',
        table_name_in        => 'ORDERS',
        partition#_in        => 1,
        subpartition#_in     => 2,
        high_value_in        => 'SOUTH',
        p_name_in            => 'ORDERS_2024Q1_SOUTH',
        tbs_name_in          => 'DATA_2024',
        enabled_in           => 1
    );
END;
/
```

---

## Usage Examples

### Running the Partition Handler

**Interactive Execution**:
```sql
BEGIN
    partition_handler.handle_partitions;
END;
/
```

**View Test Script**:
```sql
@test-it.sql
```

### Scheduled Execution via DBMS_SCHEDULER

```sql
BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'PARTITION_HANDLER_JOB',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN partition_handler.handle_partitions; END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY; BYHOUR=2; BYMINUTE=0',  -- Run at 2 AM daily
        enabled         => TRUE,
        comments        => 'Automated partition management'
    );
END;
/
```

### Monitoring Execution

**Check Last Run Status**:
```sql
SELECT object_type,
       object_owner,
       object_name,
       enabled,
       order#,
       last_run_start_ts,
       last_run_end_ts,
       last_run_duration
FROM partition_object
ORDER BY last_run_start_ts DESC NULLS LAST;
```

**View Partition Definitions**:
```sql
SELECT d.partition#,
       d.subpartition#,
       d.p_name,
       d.high_value,
       d.tbs_name,
       d.enabled,
       d.auto_adjust_enabled,
       d.moving_window
FROM p_obj o
JOIN p_def d ON d.p_obj_id = o.id
WHERE o.owner = 'MYSCHEMA'
  AND o.name = 'SALES_DATA'
ORDER BY d.partition#, d.subpartition#;
```

**Check Actual Partitions**:
```sql
SELECT partition_name,
       high_value,
       tablespace_name,
       num_rows
FROM dba_tab_partitions
WHERE table_owner = 'MYSCHEMA'
  AND table_name = 'SALES_DATA'
ORDER BY partition_position;
```

### Disabling/Enabling Objects

**Temporarily Disable an Object**:
```sql
BEGIN
    partition_config.disable_table(
        owner_in      => 'MYSCHEMA',
        table_name_in => 'SALES_DATA'
    );
    COMMIT;
END;
/
```

**Re-enable**:
```sql
BEGIN
    partition_config.enable_table(
        owner_in      => 'MYSCHEMA',
        table_name_in => 'SALES_DATA'
    );
    COMMIT;
END;
/
```

---

## Extension & Enhancement Guide

### Architecture Overview for Developers

The system follows a **layered architecture**:

1. **Configuration Layer** (`P_*` tables): Stores declarative partition definitions
2. **API Layer** (`PARTITION_CONFIG`): Provides CRUD operations for configuration
3. **Processing Layer** (`PARTITION_HANDLER`): Orchestrates partition operations
4. **Utility Layer** (`PARTITION_TOOLS`, `PARTITION_REDEFINE`): Specialized functions
5. **Type Layer** (`PARTITION_TYPES`, `PARTITION_CONSTANTS`): Shared definitions

### Adding New Partition Techniques

**Example: Add support for SYSTEM partitioning**

1. **Add to P_TECH table**:
```sql
INSERT INTO p_tech (id, name, description)
VALUES (6, 'SYSTEM', 'Partitioned by Oracle system control');
COMMIT;
```

2. **Add constant to PARTITION_CONSTANTS**:
```sql
c_par_tech_system_id CONSTANT PLS_INTEGER := 6;
c_par_tech_system    CONSTANT p_tech.name%TYPE := 'SYSTEM';
```

3. **Update PARTITION_HANDLER logic**:
   - Modify `object_is_well_partitioned()` to validate SYSTEM partitioning
   - Update `get_partition_ddl()` to generate correct DDL syntax
   - Handle SYSTEM-specific operations in partition management methods

4. **Update PARTITION_CONFIG**:
   - Ensure partition key configuration validates SYSTEM requirements
   - Add helper procedures if needed for SYSTEM-specific setup

### Adding Custom Auto-Adjust Functions

The `auto_adjust_function` field accepts any function that calculates new boundaries.

**Example: Custom fiscal year calculation**

1. **Create the function**:
```sql
CREATE OR REPLACE FUNCTION calculate_fiscal_period(
    base_date        IN DATE,
    increment_value  IN VARCHAR2
) RETURN DATE IS
    l_fiscal_start DATE;
    l_increment    NUMBER := TO_NUMBER(increment_value);
BEGIN
    -- Fiscal year starts April 1
    l_fiscal_start := TRUNC(base_date, 'YYYY');
    IF EXTRACT(MONTH FROM base_date) < 4 THEN
        l_fiscal_start := ADD_MONTHS(l_fiscal_start, -12);
    END IF;
    l_fiscal_start := l_fiscal_start + INTERVAL '3' MONTH;
    
    RETURN ADD_MONTHS(l_fiscal_start, l_increment * 12);
END;
/
```

2. **Configure partition to use it**:
```sql
BEGIN
    partition_config.add_table_partition(
        -- ... other parameters
        auto_adjust_function_in => 'CALCULATE_FISCAL_PERIOD',
        auto_adjust_value_in    => '1',  -- Fiscal year increment
        -- ...
    );
END;
/
```

### Adding Custom Naming Functions

Naming functions generate partition or tablespace names dynamically.

**Example: Custom naming with business logic**

1. **Create naming function**:
```sql
CREATE OR REPLACE FUNCTION generate_partition_name(
    name_format     IN VARCHAR2,
    high_value_date IN TIMESTAMP WITH LOCAL TIME ZONE,
    prefix          IN VARCHAR2 DEFAULT NULL,
    suffix          IN VARCHAR2 DEFAULT NULL
) RETURN VARCHAR2 IS
    l_name VARCHAR2(30);
BEGIN
    -- Custom logic: Abbreviate month names
    l_name := TO_CHAR(high_value_date, 'YYYY') || 
              CASE EXTRACT(MONTH FROM high_value_date)
                  WHEN 1 THEN 'JAN'
                  WHEN 2 THEN 'FEB'
                  -- ... etc
              END;
    
    RETURN NVL(prefix, '') || l_name || NVL(suffix, '');
END;
/
```

2. **Use in configuration**:
```sql
p_name_in             => 'P_',  -- Format template
p_name_prefix_in      => 'SALES_',
p_naming_function_in  => 'GENERATE_PARTITION_NAME'
```

### Extending Redefinition Logic

To customize online redefinition behavior:

1. **Edit `partition_redefine.pck`**:
   - Modify `redefine_table()` to add pre/post redefinition hooks
   - Customize `get_create_table_ddl()` for special table structures
   - Add custom index handling in `get_index_ddls()`

2. **Example: Add statistics preservation**:
```sql
-- In redefine_table(), after creating interim table:
DBMS_STATS.COPY_TABLE_STATS(
    ownname          => owner_in,
    tabname          => table_name_in,
    srcpartname      => NULL,
    dstpartname      => NULL,
    dstownname       => owner_in,
    dsttabname       => interim_table_name_in,
    scale_factor     => 1
);
```

### Adding New Process Actions

To add new partition operations:

1. **Define constant in PARTITION_HANDLER**:
```sql
c_pa_must_coalesce CONSTANT PLS_INTEGER := 14;
c_pa_coalesced     CONSTANT PLS_INTEGER := 15;
```

2. **Create operation procedure**:
```sql
PROCEDURE coalesce_partition(
    obj_def_in  IN partition_object%ROWTYPE,
    part_def_in IN partition_types.t_partition_def
) IS
BEGIN
    -- Implementation
    sql_admin.execute_sql('ALTER TABLE ... COALESCE PARTITION');
END coalesce_partition;
```

3. **Integrate into `handle_object_partitions()`**:
```sql
IF l_action = c_pa_must_coalesce THEN
    coalesce_partition(obj_def_in => obj_def_in, part_def_in => l_part_defs(i));
END IF;
```

### Performance Tuning Considerations

**Parallel Execution**:
- Default parallel degree is 4 (`c_default_parallel_degree`)
- Configure via `module_admin`: `MODULE_ADMIN.SET_MODULE_VALUE('PARTITION_HANDLER', 'DEGREE', '8')`
- Higher parallelism = faster operations but more resource usage

**DDL Lock Timeout**:
- Default timeout is 300 seconds
- Prevents indefinite hangs on locked objects
- Objects already locked will be skipped

**Batch Processing**:
- Objects are processed serially by `order#`
- Process high-priority tables first by setting low `order#` values
- Consider splitting large jobs across multiple scheduler windows

**Index Management**:
- Global index updates (`UPDATE GLOBAL INDEXES`) add overhead
- Consider rebuilding global indexes offline during maintenance windows
- Use `LOCAL` indexes where possible to avoid global index maintenance

### Error Handling and Logging

The system uses the `log_admin` package for comprehensive logging.

**Log Levels**:
- `DEBUG`: Detailed execution flow
- `INFO`: Normal operations
- `WARNING`: Non-critical issues
- `ERROR`: Recoverable errors
- `CRITICAL`: Fatal errors

**Accessing Logs**:
```sql
-- View recent partition handler logs
SELECT timestamp,
       log_level,
       module_name,
       module_action,
       message
FROM log_entries
WHERE module_name = 'PARTITION_HANDLER'
ORDER BY timestamp DESC;
```

**Custom Error Handling**:
To add custom error handling, wrap calls in exception blocks:

```sql
BEGIN
    partition_handler.handle_partitions;
EXCEPTION
    WHEN OTHERS THEN
        -- Custom notification logic
        send_alert_email('Partition handler failed: ' || SQLERRM);
        RAISE;
END;
```

---

## Key Design Patterns

### 1. **Configuration-Driven Processing**
All partition definitions are stored declaratively in database tables. The handler reads configurations and generates/executes DDL dynamically. This separates "what" (configuration) from "how" (implementation).

### 2. **Cursor-Based Bulk Processing**
Uses explicit cursors with `BULK COLLECT` to efficiently load large datasets into memory before processing.

### 3. **Template Method Pattern**
`handle_object()` defines the skeleton of partition processing. Specific operations (add, split, merge) are delegated to specialized methods.

### 4. **Strategy Pattern**
Different partitioning techniques (RANGE, LIST, HASH) are handled through technique ID lookups, allowing new techniques to be added without modifying core logic.

### 5. **Exception Translation**
Oracle-specific exceptions (e.g., ORA-00904) are caught via `PRAGMA EXCEPTION_INIT` and translated to business-meaningful errors.

### 6. **Idempotency**
The handler can be run multiple times safely. It compares desired state (configuration) with actual state (database) and only makes necessary changes.

### 7. **Separation of Concerns**
- **PARTITION_CONFIG**: Configuration management
- **PARTITION_HANDLER**: Orchestration and DDL execution
- **PARTITION_REDEFINE**: Complex redefinition logic
- **PARTITION_TOOLS**: Reusable utilities
- **PARTITION_TYPES**: Shared types

### 8. **Dependency Injection via Packages**
Dependencies (`log_admin`, `module_admin`, `sql_admin`) are external packages, allowing easy replacement or mocking for testing.

---

## Troubleshooting

### Common Issues

#### 1. **"Configuration check required" Errors**

**Cause**: Mismatch between configured partitions and actual database structure.

**Solution**:
```sql
-- Check if table/index exists
SELECT owner, object_name, object_type, status
FROM dba_objects
WHERE owner = 'MYSCHEMA' AND object_name = 'SALES_DATA';

-- Check partition key configuration
SELECT k.column_name, t.name AS technique
FROM p_obj o
JOIN p_key k ON k.p_obj_id = o.id
JOIN p_tech t ON t.id = k.p_tech_id
WHERE o.owner = 'MYSCHEMA' AND o.name = 'SALES_DATA';

-- Verify column exists in table
SELECT column_name, data_type
FROM dba_tab_columns
WHERE owner = 'MYSCHEMA' AND table_name = 'SALES_DATA';
```

#### 2. **"Object does not exist" Error**

**Cause**: Configured object was dropped or renamed.

**Solution**:
```sql
-- Remove from configuration
BEGIN
    partition_config.del_table(owner_in => 'MYSCHEMA', table_name_in => 'OLD_TABLE');
    COMMIT;
END;
/
```

#### 3. **"Index online redefinition not supported"**

**Cause**: Attempting to redefine a partitioned index structure.

**Solution**: Indexes cannot be redefined online. Either:
- Drop and recreate the index with correct partitioning
- Use `ALTER INDEX ... REBUILD` for compatible changes

#### 4. **ORA-14074: Partition Bound Must Collate Higher**

**Cause**: New partition boundary is not higher than the previous partition.

**Solution**: Ensure `partition#` and `high_value` are in ascending order:
```sql
SELECT partition#, high_value, p_name
FROM p_def
WHERE p_obj_id = (SELECT id FROM p_obj WHERE owner = 'MYSCHEMA' AND name = 'SALES_DATA')
ORDER BY partition#;
```

#### 5. **ORA-00959: Tablespace Does Not Exist**

**Cause**: Configured tablespace doesn't exist.

**Solution**:
```sql
-- Check tablespace exists
SELECT tablespace_name FROM dba_tablespaces;

-- Update configuration
UPDATE p_def SET tbs_name = 'VALID_TABLESPACE'
WHERE p_obj_id = ... AND partition# = ...;
COMMIT;
```

#### 6. **Performance Issues / Long Execution Time**

**Diagnosis**:
```sql
-- Check which objects are taking longest
SELECT object_owner,
       object_name,
       last_run_duration
FROM partition_object
ORDER BY last_run_duration DESC NULLS LAST;
```

**Solutions**:
- Increase parallel degree
- Process problem objects outside business hours
- Split large tables into smaller partition ranges
- Check for lock contention

#### 7. **DDL Lock Timeout**

**Cause**: Another session is holding a lock on the object.

**Diagnosis**:
```sql
SELECT s.sid, s.serial#, s.username, s.program,
       o.object_name, l.locked_mode
FROM v$locked_object l
JOIN dba_objects o ON o.object_id = l.object_id
JOIN v$session s ON s.sid = l.session_id
WHERE o.object_name = 'SALES_DATA';
```

**Solution**:
- Wait for locks to clear
- Increase `DDL_LOCK_TIMEOUT` session parameter
- Kill blocking sessions if necessary (with caution)

### Debugging Tips

**Enable Debug Logging**:
```sql
-- Temporarily enable debug mode in log_admin
BEGIN
    log_admin.set_log_level('DEBUG');
END;
/

-- Run handler
BEGIN
    partition_handler.handle_partitions;
END;
/

-- Check debug logs
SELECT * FROM log_entries 
WHERE module_name = 'PARTITION_HANDLER'
  AND log_level = 'DEBUG'
ORDER BY timestamp DESC;
```

**Dry Run / Test Mode**:
To test without executing DDL, temporarily modify `sql_admin.execute_sql()` to log instead of execute:

```sql
-- In sql_admin package
PROCEDURE execute_sql(sql_in IN VARCHAR2) IS
BEGIN
    -- log_admin.info('DRY RUN: ' || sql_in);  -- Uncomment for dry run
    EXECUTE IMMEDIATE sql_in;  -- Comment out for dry run
END;
```

**Manual DDL Extraction**:
You can extract the DDL that would be generated:

```sql
-- View generated partition creation DDL
SELECT 'ALTER TABLE ' || object_owner || '.' || object_name || 
       ' ADD PARTITION ' || p_name || 
       ' VALUES LESS THAN (' || high_value || ')' ||
       ' TABLESPACE ' || tbs_name AS ddl_statement
FROM partition_object o
JOIN p_def d ON d.p_obj_id = o.object_id
WHERE o.object_owner = 'MYSCHEMA'
  AND o.object_name = 'SALES_DATA';
```

---

## Dependencies

### Required Packages

1. **log_admin** (v1.2.3+)
   - Purpose: Logging and auditing framework
   - Methods: `info()`, `debug()`, `warning()`, `error()`, `critical()`

2. **module_admin** (v0.7.1+)
   - Purpose: Module configuration management
   - Methods: `load_and_set_config()`, `get_module_value()`, `set_module_value()`

3. **sql_admin**
   - Purpose: Dynamic SQL execution with error handling
   - Methods: `execute_sql()`

4. **object_admin**
   - Purpose: Database object management utilities
   - Methods: `is_object_existing()`, `rebuild_unusable_indexes()`

### Optional Enhancements

- **DBMS_SCHEDULER**: For automated scheduling
- **Email/Alert Framework**: For notification on errors
- **Monitoring Tools**: Integration with enterprise monitoring (Nagios, Zabbix, etc.)

---

## Refactoring Opportunities

### High-Priority Improvements

1. **Separate DDL Generation from Execution**
   - **Current**: DDL is constructed and executed in same method
   - **Proposed**: Create `partition_ddl_builder` package
   - **Benefit**: Easier testing, dry-run mode, DDL export capability

2. **Implement Transaction Boundaries**
   - **Current**: Some operations auto-commit (DDL), others don't
   - **Proposed**: Clearly document transaction boundaries, add savepoints
   - **Benefit**: Better error recovery, partial rollback capability

3. **Add Unit Testing Framework**
   - **Current**: Only manual testing via `test-it.sql`
   - **Proposed**: Use utPLSQL or similar for automated unit tests
   - **Benefit**: Regression testing, CI/CD integration

4. **Extract Business Logic from SQL**
   - **Current**: Complex logic in cursor SQL (e.g., `cur_part_defs`)
   - **Proposed**: Move to view or separate function
   - **Benefit**: Easier to understand and maintain

5. **Configuration Validation**
   - **Current**: Validation happens during execution
   - **Proposed**: Add `partition_config.validate_object()` procedure
   - **Benefit**: Catch errors before runtime

### Medium-Priority Improvements

6. **Partition Statistics Management**
   - Add automatic statistics gathering post-partition operations
   - Preserve statistics during redefinition

7. **Enhanced Monitoring**
   - Add performance metrics (execution time per object)
   - Track partition growth rates
   - Predictive analysis for auto-adjust

8. **Parallel Object Processing**
   - Currently objects are processed serially
   - Consider parallel processing of independent objects using DBMS_SCHEDULER

9. **RESTful API Wrapper**
   - Expose partition configuration via REST API
   - Enable external system integration

10. **Partition Compression Management**
    - Auto-compress old partitions
    - Configure compression per partition range

### Code Quality Improvements

- **Reduce Cyclomatic Complexity**: `handle_object()` method is 400+ lines
- **Extract Magic Numbers**: Many hardcoded values should be constants
- **Improve Error Messages**: Add more context to error logs
- **Documentation**: Add inline comments for complex logic
- **Naming Consistency**: Some variables use Hungarian notation, others don't

---

## License

This project is authored by Thomas Krahn. Please refer to your organization's licensing terms for usage restrictions.

---

## Contact & Support

For questions, enhancements, or bug reports:

1. Review this README thoroughly
2. Check the `log_entries` table for error details
3. Consult the inline package comments
4. Contact the database administration team

---

## Appendix: Quick Reference

### Partition Technique IDs
| ID | Name      | Description                           |
|----|-----------|---------------------------------------|
| 1  | LIST      | Discrete value partitioning           |
| 2  | RANGE     | Range-based partitioning              |
| 3  | HASH      | Hash-based partitioning               |
| 4  | INTERVAL  | Automatic range partitioning          |
| 5  | REFERENCE | Parent-child partitioning             |
| 6  | AUTO_LIST | Automatic LIST partition (19c) ⭐     |

### Object Type IDs
| ID | Name  |
|----|-------|
| 1  | TABLE |
| 2  | INDEX |

### Partition Type IDs
| ID | Name         |
|----|--------------|
| 1  | PARTITION    |
| 2  | SUBPARTITION |

### Common Date Formats
- `YYYY-MM-DD` - ISO date format
- `YYYYMMDD` - Compact date
- `YYYY-MM-DD HH24:MI:SS` - Timestamp format
- `SYYYY-MM-DD HH24:MI:SS.FF6 TZR` - Full timestamp with timezone

### Useful Queries

**List All Configured Objects**:
```sql
SELECT * FROM partition_object ORDER BY object_type, object_owner, object_name;
```

**List All Partition Definitions**:
```sql
SELECT o.owner, o.name, d.*
FROM p_obj o JOIN p_def d ON d.p_obj_id = o.id
ORDER BY o.owner, o.name, d.partition#, d.subpartition#;
```

**Compare Config vs Actual**:
```sql
-- Configured partitions
SELECT p_name FROM p_def WHERE p_obj_id = :obj_id
MINUS
-- Actual partitions  
SELECT partition_name FROM dba_tab_partitions WHERE table_owner = :owner AND table_name = :name;
```

---

**End of README**
