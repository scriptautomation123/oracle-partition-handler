# Oracle 19c Partition Handler - New Features Guide

## Overview

This guide documents the Oracle 19c-specific partition handling features added to the Oracle Partition Handler framework. These features leverage Oracle 19c's enhanced partitioning capabilities and provide modern, robust table conversion utilities.

**Version**: 1.0.0  
**Package**: `PARTITION_REDEFINE_19C`  
**Requirements**: Oracle Database 19c or higher

---

## Table of Contents

1. [New Partition Techniques](#new-partition-techniques)
2. [Composite Partitioning Support](#composite-partitioning-support)
3. [Conversion Operations](#conversion-operations)
4. [Online vs Offline Conversion](#online-vs-offline-conversion)
5. [Usage Examples](#usage-examples)
6. [API Reference](#api-reference)
7. [Best Practices](#best-practices)

---

## New Partition Techniques

### AUTO_LIST Partitioning (Oracle 19c)

AUTO_LIST is a new partitioning method introduced in Oracle 19c that automatically creates LIST partitions for new values.

**Key Features:**
- Automatic partition creation when new values are inserted
- No need to pre-define all partition values
- Ideal for categorical data with evolving values
- Supports both single-level and composite partitioning

**Benefits:**
- Eliminates manual partition maintenance
- Prevents "partition not found" errors
- Simplifies partition management for dynamic datasets

**Technical ID**: 6 in `P_TECH` table

**Example Table Structure:**
```sql
CREATE TABLE sales_by_region (
    region_code VARCHAR2(10),
    sale_date DATE,
    amount NUMBER
)
PARTITION BY AUTO LIST (region_code);
```

---

## Composite Partitioning Support

Oracle 19c extends composite partitioning to include HASH as a primary partition method.

### HASH-Based Composite Partitioning

#### HASH-RANGE
Distributes data evenly across hash partitions, then subdivides by range.

**Use Case:** High-volume transactional data with time-based queries
```sql
PARTITION BY HASH (customer_id)
SUBPARTITION BY RANGE (order_date)
```

#### HASH-HASH
Double-hashing for maximum parallelism and load distribution.

**Use Case:** Extremely high-volume systems requiring parallel processing
```sql
PARTITION BY HASH (customer_id)
SUBPARTITION BY HASH (order_id)
```

#### HASH-LIST
Hash distribution with categorical subdivisions.

**Use Case:** Multi-tenant systems with regional distribution
```sql
PARTITION BY HASH (tenant_id)
SUBPARTITION BY LIST (region_code)
```

### Existing Composite Partitioning (Enhanced)

The package also supports all traditional composite partitioning methods:

- **RANGE-RANGE**: Time-series with finer granularity
- **RANGE-HASH**: Time-series with hash distribution
- **RANGE-LIST**: Time-series with categorical subdivision
- **LIST-RANGE**: Categories with time-based subdivision
- **LIST-HASH**: Categories with hash distribution
- **LIST-LIST**: Multi-level categorical partitioning

---

## Conversion Operations

The `PARTITION_REDEFINE_19C` package provides three main conversion operations:

### 1. Convert Regular Table to Single-Level Partitioning

**Function**: `convert_to_single_level_partition`

Converts a non-partitioned table to use single-level partitioning (RANGE, LIST, HASH, INTERVAL, REFERENCE, or AUTO_LIST).

**Parameters:**
- `owner_in`: Schema owner
- `table_name_in`: Table to convert
- `partition_spec`: Partition specification
- `part_defs_in`: Partition definitions
- `options_in`: Conversion options (online/offline, parallel, etc.)

**Returns:** TRUE if successful, FALSE otherwise

### 2. Convert Regular Table to Composite Partitioning

**Function**: `convert_to_composite_partition`

Converts a non-partitioned table to use two-level composite partitioning.

**Parameters:** Same as above, but `partition_spec` must include subpartition information

**Returns:** TRUE if successful, FALSE otherwise

### 3. Convert Single-Level to Composite Partitioning

**Function**: `convert_single_to_composite`

Converts an existing single-level partitioned table to composite partitioning.

**Parameters:** Same as above

**Returns:** TRUE if successful, FALSE otherwise

---

## Online vs Offline Conversion

The package automatically determines the best conversion strategy based on table characteristics.

### Online Conversion

**Capabilities:**
- Minimal downtime (only during final rename)
- Incremental data sync
- Table remains accessible during conversion
- Requires primary key or unique constraint

**When Used:**
- Table has primary key
- AUTO_LIST partitioning
- HASH-based composite partitioning
- No blocking operations required

**Advantages:**
- Near-zero downtime
- Minimal impact on production
- Automatic rollback on failure

### Offline Conversion

**Capabilities:**
- Full table lock during conversion
- Single data copy operation
- No incremental sync needed
- Works without primary key

**When Used:**
- Table lacks primary key
- Specific partition types require it
- Explicitly requested via options
- Very small tables (faster than online)

**Advantages:**
- Simpler process
- Faster for small tables
- No tracking requirements

---

## Usage Examples

### Example 1: Convert to AUTO_LIST Partitioning

```sql
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
BEGIN
  -- Define partition specification
  v_partition_spec.partition_type := 'AUTO_LIST';
  v_partition_spec.partition_key := 'REGION_CODE';
  v_partition_spec.is_composite := FALSE;
  v_partition_spec.online_capable := TRUE;
  v_partition_spec.requires_pk := TRUE;
  
  -- Define initial partitions (AUTO_LIST will create more as needed)
  v_part_defs(1).partition_name := 'P_WEST';
  v_part_defs(1).high_value := '''WEST''';
  v_part_defs(1).tablespace_name := 'USERS';
  v_part_defs(1).partition_type_id := 1;
  
  v_part_defs(2).partition_name := 'P_EAST';
  v_part_defs(2).high_value := '''EAST''';
  v_part_defs(2).tablespace_name := 'USERS';
  v_part_defs(2).partition_type_id := 1;
  
  -- Configure conversion options
  v_options.strategy := 'ONLINE';
  v_options.copy_constraints := TRUE;
  v_options.copy_indexes := TRUE;
  v_options.validate_constraints := TRUE;
  
  -- Execute conversion
  v_success := partition_redefine_19c.convert_to_single_level_partition(
    owner_in       => 'MYSCHEMA',
    table_name_in  => 'SALES',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF v_success THEN
    DBMS_OUTPUT.PUT_LINE('Conversion successful!');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Conversion failed!');
  END IF;
END;
/
```

### Example 2: Convert to HASH-RANGE Composite Partitioning

```sql
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
  v_idx            PLS_INTEGER := 0;
BEGIN
  -- Define composite partition specification
  v_partition_spec.partition_type := 'HASH';
  v_partition_spec.partition_key := 'CUSTOMER_ID';
  v_partition_spec.subpartition_type := 'RANGE';
  v_partition_spec.subpartition_key := 'ORDER_DATE';
  v_partition_spec.is_composite := TRUE;
  v_partition_spec.online_capable := TRUE;
  v_partition_spec.requires_pk := TRUE;
  
  -- Define hash partitions with range subpartitions
  -- Partition 1 (hash)
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_HASH_1';
  v_part_defs(v_idx).partition_type_id := 1; -- PARTITION
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Subpartition 1-1 (range)
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q1';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := 2; -- SUBPARTITION
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Subpartition 1-2 (range)
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q2';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-07-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := 2; -- SUBPARTITION
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Partition 2 (hash) - repeat subpartitions
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_HASH_2';
  v_part_defs(v_idx).partition_type_id := 1; -- PARTITION
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q1';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := 2;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q2';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-07-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := 2;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Configure for online conversion with parallel processing
  v_options.strategy := 'ONLINE';
  v_options.enable_parallel := TRUE;
  v_options.parallel_degree := 4;
  
  -- Execute conversion
  v_success := partition_redefine_19c.convert_to_composite_partition(
    owner_in       => 'MYSCHEMA',
    table_name_in  => 'ORDERS',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF v_success THEN
    DBMS_OUTPUT.PUT_LINE('Composite partitioning conversion successful!');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Composite partitioning conversion failed!');
  END IF;
END;
/
```

### Example 3: Check Online Capability Before Conversion

```sql
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_is_online      BOOLEAN;
BEGIN
  v_partition_spec.partition_type := 'RANGE';
  v_partition_spec.partition_key := 'SALE_DATE';
  v_partition_spec.is_composite := FALSE;
  v_partition_spec.requires_pk := TRUE;
  
  v_is_online := partition_redefine_19c.is_online_conversion_capable(
    owner_in       => 'MYSCHEMA',
    table_name_in  => 'SALES',
    partition_spec => v_partition_spec
  );
  
  IF v_is_online THEN
    DBMS_OUTPUT.PUT_LINE('Table can be converted online');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Table requires offline conversion');
  END IF;
END;
/
```

### Example 4: Cleanup Object Names After Conversion

```sql
BEGIN
  -- After conversion is complete and verified, clean up _NEW suffixes
  partition_redefine_19c.cleanup_object_names(
    owner_in      => 'MYSCHEMA',
    table_name_in => 'ORDERS'
  );
  
  DBMS_OUTPUT.PUT_LINE('Object names cleaned up successfully');
END;
/
```

---

## API Reference

### Types

#### t_partition_spec
Record type defining partition structure:
```sql
TYPE t_partition_spec IS RECORD(
  partition_type      VARCHAR2(20),    -- RANGE, LIST, HASH, INTERVAL, REFERENCE, AUTO_LIST
  subpartition_type   VARCHAR2(20),    -- NULL or RANGE/LIST/HASH for composite
  partition_key       VARCHAR2(4000),  -- Column(s) for partitioning
  subpartition_key    VARCHAR2(4000),  -- Column(s) for subpartitioning
  is_composite        BOOLEAN,         -- TRUE if composite
  online_capable      BOOLEAN,         -- TRUE if online conversion possible
  requires_pk         BOOLEAN          -- TRUE if PK required
);
```

#### t_conversion_options
Record type for conversion options:
```sql
TYPE t_conversion_options IS RECORD(
  strategy            VARCHAR2(10),    -- 'ONLINE' or 'OFFLINE'
  interim_suffix      VARCHAR2(30) DEFAULT '_NEW',
  old_suffix          VARCHAR2(30) DEFAULT '_OLD',
  copy_constraints    BOOLEAN DEFAULT TRUE,
  copy_indexes        BOOLEAN DEFAULT TRUE,
  copy_triggers       BOOLEAN DEFAULT TRUE,
  validate_constraints BOOLEAN DEFAULT TRUE,
  max_sync_iterations INTEGER DEFAULT 10,
  enable_parallel     BOOLEAN DEFAULT FALSE,
  parallel_degree     INTEGER DEFAULT 4
);
```

### Functions

#### convert_to_single_level_partition
Converts non-partitioned table to single-level partitioning.

**Signature:**
```sql
FUNCTION convert_to_single_level_partition(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2,
  partition_spec   IN t_partition_spec,
  part_defs_in     IN partition_types.t_partition_def_table,
  options_in       IN t_conversion_options DEFAULT NULL
) RETURN BOOLEAN;
```

#### convert_to_composite_partition
Converts non-partitioned table to composite partitioning.

**Signature:**
```sql
FUNCTION convert_to_composite_partition(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2,
  partition_spec   IN t_partition_spec,
  part_defs_in     IN partition_types.t_partition_def_table,
  options_in       IN t_conversion_options DEFAULT NULL
) RETURN BOOLEAN;
```

#### convert_single_to_composite
Converts single-level partitioned table to composite.

**Signature:**
```sql
FUNCTION convert_single_to_composite(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2,
  partition_spec   IN t_partition_spec,
  part_defs_in     IN partition_types.t_partition_def_table,
  options_in       IN t_conversion_options DEFAULT NULL
) RETURN BOOLEAN;
```

#### is_online_conversion_capable
Checks if online conversion is possible.

**Signature:**
```sql
FUNCTION is_online_conversion_capable(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2,
  partition_spec   IN t_partition_spec
) RETURN BOOLEAN;
```

#### generate_partition_ddl_19c
Generates partition DDL clause.

**Signature:**
```sql
FUNCTION generate_partition_ddl_19c(
  partition_spec   IN t_partition_spec,
  part_defs_in     IN partition_types.t_partition_def_table
) RETURN CLOB;
```

### Procedures

#### execute_conversion_with_sync
Executes full conversion workflow with sync and rename.

**Signature:**
```sql
PROCEDURE execute_conversion_with_sync(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2,
  new_table_ddl    IN CLOB,
  options_in       IN t_conversion_options DEFAULT NULL
);
```

**Workflow:**
1. Create new table with `_NEW` suffix
2. Copy constraints (disabled)
3. Copy indexes
4. Initial data load (INSERT INTO SELECT)
5. Incremental sync (for online strategy)
6. Enable and validate constraints
7. Atomic rename (original → `_OLD`, `_NEW` → original)

#### cleanup_object_names
Renames indexes and constraints from `_NEW` to original names.

**Signature:**
```sql
PROCEDURE cleanup_object_names(
  owner_in         IN VARCHAR2,
  table_name_in    IN VARCHAR2
);
```

---

## Best Practices

### 1. Pre-Conversion Assessment

**Always check online capability first:**
```sql
v_is_online := partition_redefine_19c.is_online_conversion_capable(...);
```

**Verify table has adequate storage:**
- Conversion requires space for both original and new table
- Budget at least 2x current table size

**Check dependencies:**
- Foreign key constraints
- Materialized views
- Database links
- Application connections

### 2. Partition Strategy Selection

**Use AUTO_LIST when:**
- Values are categorical and evolving
- You cannot predict all possible values
- New values are frequently added

**Use HASH-based composite when:**
- Extremely high transaction volume
- Need maximum parallel processing
- Query patterns don't benefit from range pruning

**Use RANGE-based composite when:**
- Time-series data is primary access pattern
- Need partition pruning for performance
- Historical data can be archived/dropped

### 3. Online Conversion Best Practices

**Minimize downtime:**
- Schedule during low-activity periods
- Use parallel processing for large tables
- Monitor sync iterations

**Handle failures gracefully:**
- Always have rollback plan
- Keep `_OLD` table until verified
- Document each step

**Verify after conversion:**
```sql
-- Check partition structure
SELECT * FROM user_tab_partitions WHERE table_name = 'YOUR_TABLE';

-- Verify data integrity
SELECT COUNT(*) FROM your_table;
SELECT COUNT(*) FROM your_table_old;

-- Check indexes
SELECT * FROM user_indexes WHERE table_name = 'YOUR_TABLE';
```

### 4. Performance Optimization

**Use parallel processing:**
```sql
v_options.enable_parallel := TRUE;
v_options.parallel_degree := 8; -- Adjust based on CPUs
```

**Consider partition-wise operations:**
- After conversion, use partition-specific operations
- Leverage partition pruning in queries
- Use local indexes for better partition independence

**Monitor resource usage:**
- Watch temp tablespace during conversion
- Monitor I/O patterns
- Check parallel execution statistics

### 5. Maintenance Post-Conversion

**Regular tasks:**
- Monitor partition growth (AUTO_LIST)
- Drop old partitions (with moving window)
- Rebuild indexes as needed
- Update statistics

**Cleanup after verification:**
```sql
-- After thorough testing, drop old table
DROP TABLE myschema.orders_old PURGE;

-- Clean up object names
BEGIN
  partition_redefine_19c.cleanup_object_names(
    owner_in      => 'MYSCHEMA',
    table_name_in => 'ORDERS'
  );
END;
/
```

---

## Troubleshooting

### Common Issues

#### Issue: "Online conversion not supported"
**Cause:** Table lacks primary key  
**Solution:** Add primary key or use offline conversion

#### Issue: "Insufficient storage"
**Cause:** Not enough space for both tables  
**Solution:** Free up space or use smaller parallel degree

#### Issue: "Constraint validation failed"
**Cause:** Data doesn't meet constraint requirements  
**Solution:** Fix data issues before conversion or use `validate_constraints => FALSE`

#### Issue: "Sync timeout"
**Cause:** Too many changes during online conversion  
**Solution:** Reduce activity or use offline conversion

### Error Handling

All functions return BOOLEAN indicating success/failure. Check logs for details:

```sql
SELECT * FROM log_admin.log_entry
 WHERE module_name = 'PARTITION_REDEFINE_19C'
 ORDER BY log_timestamp DESC;
```

---

## Migration Path from Legacy Code

If you're using the older `PARTITION_REDEFINE` package, consider:

1. **New tables**: Use `PARTITION_REDEFINE_19C` for all new conversions
2. **Existing tables**: Continue using `PARTITION_REDEFINE` until migration
3. **19c features**: Only `PARTITION_REDEFINE_19C` supports AUTO_LIST and HASH composite
4. **Gradual migration**: Both packages can coexist

---

## Version History

### Version 1.0.0 (2024)
- Initial release
- AUTO_LIST partition support
- HASH-based composite partitioning
- Online/offline conversion strategies
- Incremental sync mechanism
- Comprehensive error handling
- Full Oracle 19c compatibility

---

## Support and Contributions

For issues, questions, or contributions:
- Review existing codebase in `partition_handler.pck` and `partition_redefine.pck`
- Follow existing patterns for consistency
- Add comprehensive logging using `log_admin` package
- Document all new features

---

## License

Same as parent Oracle Partition Handler framework.
