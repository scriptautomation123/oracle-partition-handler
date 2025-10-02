# Migration Guide: Legacy to Oracle 19c Partition Handler

## Overview

This guide helps you migrate from the legacy `PARTITION_REDEFINE` package to the new `PARTITION_REDEFINE_19C` package, which provides enhanced Oracle 19c features and improved conversion capabilities.

---

## Why Migrate?

### New Features in PARTITION_REDEFINE_19C

✅ **AUTO_LIST Partitioning** - Automatic partition creation for new values  
✅ **HASH-Based Composite Partitioning** - HASH-RANGE, HASH-HASH, HASH-LIST  
✅ **Online/Offline Strategy Control** - Choose conversion approach  
✅ **Parallel Processing Support** - Faster conversions for large tables  
✅ **Incremental Sync Mechanism** - Minimal downtime for online conversions  
✅ **Better Error Handling** - More detailed logging and recovery options  
✅ **Flexible Options** - Fine-grained control over conversion process  

### When NOT to Migrate

❌ Running Oracle 11g or 12c (not 19c)  
❌ Happy with current DBMS_REDEFINITION wrapper  
❌ No need for new 19c features  
❌ Tables use features specific to old package  

---

## Compatibility Matrix

| Feature | PARTITION_REDEFINE | PARTITION_REDEFINE_19C | Notes |
|---------|-------------------|------------------------|-------|
| RANGE partitioning | ✅ | ✅ | Same |
| LIST partitioning | ✅ | ✅ | Same |
| HASH partitioning | ✅ | ✅ | Same |
| INTERVAL partitioning | ✅ | ✅ | Same |
| REFERENCE partitioning | ✅ | ✅ | Same |
| AUTO_LIST partitioning | ❌ | ✅ | 19c only |
| RANGE-* composite | ✅ | ✅ | Same |
| LIST-* composite | ✅ | ✅ | Same |
| HASH-* composite | ❌ | ✅ | 19c only |
| Online redefinition | ✅ | ✅ | Enhanced in 19c version |
| Offline conversion | ⚠️ | ✅ | Manual in old, automatic in new |
| Parallel processing | ⚠️ | ✅ | Limited in old, full support in new |

---

## Migration Strategies

### Strategy 1: Side-by-Side (Recommended)

Keep both packages installed. Use old for existing tables, new for new conversions.

**Advantages:**
- Zero risk to existing processes
- Gradual learning curve
- Easy rollback

**Implementation:**
```sql
-- Both packages installed
-- Use old package for existing configurations
BEGIN
  partition_redefine.redefine_object(...);
END;
/

-- Use new package for new tables or 19c features
BEGIN
  v_success := partition_redefine_19c.convert_to_single_level_partition(...);
END;
/
```

### Strategy 2: Phased Migration

Migrate tables one at a time, testing thoroughly.

**Phase 1: Test Environment**
1. Install `PARTITION_REDEFINE_19C` in test
2. Test conversions on copy of production tables
3. Verify functionality
4. Document any issues

**Phase 2: Low-Risk Tables**
1. Identify non-critical tables
2. Convert using new package
3. Monitor for 1-2 weeks
4. Document lessons learned

**Phase 3: Production Migration**
1. Plan maintenance window
2. Convert critical tables
3. Monitor closely
4. Have rollback plan ready

### Strategy 3: Complete Replacement

Replace all usage of old package (only for new deployments).

**Implementation:**
```sql
-- Remove old package (after testing)
DROP PACKAGE partition_redefine;

-- Use only new package
BEGIN
  partition_redefine_19c.convert_to_single_level_partition(...);
END;
/
```

---

## Code Migration Examples

### Example 1: Basic Table Redefinition

#### Old Code (PARTITION_REDEFINE)

```sql
DECLARE
  v_obj_def   partition_object%ROWTYPE;
  v_part_defs partition_types.t_partition_def_table;
BEGIN
  -- Load object definition
  SELECT * INTO v_obj_def
    FROM partition_object
   WHERE object_owner = 'MYSCHEMA'
     AND object_name = 'SALES';
  
  -- Load partition definitions
  -- (Complex cursor logic)
  
  -- Execute redefinition
  partition_redefine.redefine_object(
    obj_def_in   => v_obj_def,
    part_defs_in => v_part_defs
  );
END;
/
```

#### New Code (PARTITION_REDEFINE_19C)

```sql
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
BEGIN
  -- Define partition specification
  v_partition_spec.partition_type := 'RANGE';
  v_partition_spec.partition_key := 'SALE_DATE';
  v_partition_spec.is_composite := FALSE;
  v_partition_spec.online_capable := TRUE;
  
  -- Define partitions
  v_part_defs(1).partition_name := 'P_2024_Q1';
  v_part_defs(1).high_value := 'TO_DATE(''2024-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(1).tablespace_name := 'USERS';
  v_part_defs(1).partition_type_id := 1;
  
  -- (Add more partitions as needed)
  
  -- Configure options
  v_options.strategy := 'ONLINE';
  v_options.enable_parallel := TRUE;
  v_options.parallel_degree := 4;
  
  -- Execute conversion
  v_success := partition_redefine_19c.convert_to_single_level_partition(
    owner_in       => 'MYSCHEMA',
    table_name_in  => 'SALES',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF NOT v_success THEN
    RAISE_APPLICATION_ERROR(-20001, 'Conversion failed');
  END IF;
END;
/
```

### Example 2: Composite Partitioning

#### Old Code (PARTITION_REDEFINE)

```sql
-- Old package: Complex setup through partition_object configuration
-- Had to configure via partition_config.add_table_partition_key
-- and partition_config.add_table_subpartition_key

BEGIN
  -- Add table
  partition_config.add_table(
    owner_in      => 'MYSCHEMA',
    table_name_in => 'ORDERS',
    enabled_in    => 1
  );
  
  -- Add partition key
  partition_config.add_table_partition_key(
    owner_in        => 'MYSCHEMA',
    table_name_in   => 'ORDERS',
    column_name_in  => 'ORDER_DATE',
    technique_id_in => 2  -- RANGE
  );
  
  -- Add subpartition key
  partition_config.add_table_subpartition_key(
    owner_in        => 'MYSCHEMA',
    table_name_in   => 'ORDERS',
    column_name_in  => 'CUSTOMER_ID',
    technique_id_in => 3  -- HASH
  );
  
  -- Add partition definitions...
  -- Then call partition_redefine.redefine_object
END;
/
```

#### New Code (PARTITION_REDEFINE_19C)

```sql
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_success        BOOLEAN;
BEGIN
  -- Define composite specification directly
  v_partition_spec.partition_type := 'RANGE';
  v_partition_spec.partition_key := 'ORDER_DATE';
  v_partition_spec.subpartition_type := 'HASH';
  v_partition_spec.subpartition_key := 'CUSTOMER_ID';
  v_partition_spec.is_composite := TRUE;
  
  -- Define partitions and subpartitions
  -- Partition 1
  v_part_defs(1).partition_name := 'P_2024_Q1';
  v_part_defs(1).high_value := 'TO_DATE(''2024-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(1).partition_type_id := 1;  -- PARTITION
  
  -- Subpartition 1-1
  v_part_defs(2).partition_name := 'SP_HASH_1';
  v_part_defs(2).partition_type_id := 2;  -- SUBPARTITION
  
  -- (Add more as needed)
  
  -- Execute conversion
  v_success := partition_redefine_19c.convert_to_composite_partition(
    owner_in       => 'MYSCHEMA',
    table_name_in  => 'ORDERS',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs
  );
END;
/
```

---

## Key Differences

### 1. Function vs Procedure

**Old**: Procedure-based (no return value)
```sql
partition_redefine.redefine_object(...);  -- Returns nothing
```

**New**: Function-based (returns success/failure)
```sql
v_success := partition_redefine_19c.convert_to_single_level_partition(...);
IF NOT v_success THEN
  -- Handle failure
END IF;
```

### 2. Configuration vs Direct Specification

**Old**: Requires configuration in P_OBJ, P_KEY, P_DEF tables
```sql
-- Must configure first
partition_config.add_table(...);
partition_config.add_table_partition_key(...);
-- Then redefine
partition_redefine.redefine_object(...);
```

**New**: Direct specification in code
```sql
-- Define everything in the call
v_partition_spec.partition_type := 'RANGE';
v_partition_spec.partition_key := 'SALE_DATE';
partition_redefine_19c.convert_to_single_level_partition(...);
```

### 3. Options Control

**Old**: Limited control, uses defaults
```sql
-- No way to specify parallel, strategy, etc.
partition_redefine.redefine_object(...);
```

**New**: Full control via options
```sql
v_options.strategy := 'ONLINE';
v_options.enable_parallel := TRUE;
v_options.parallel_degree := 8;
partition_redefine_19c.convert_to_single_level_partition(
  options_in => v_options, ...
);
```

### 4. Error Handling

**Old**: Exceptions raised directly
```sql
BEGIN
  partition_redefine.redefine_object(...);
EXCEPTION
  WHEN OTHERS THEN
    -- Handle any exception
END;
```

**New**: Boolean return + detailed logging
```sql
BEGIN
  v_success := partition_redefine_19c.convert_to_single_level_partition(...);
  IF NOT v_success THEN
    -- Check logs for details
    SELECT * FROM log_admin.log_entry 
     WHERE module_name = 'PARTITION_REDEFINE_19C'
     ORDER BY log_timestamp DESC;
  END IF;
END;
```

---

## Testing Checklist

Before migrating production tables:

- [ ] Install `PARTITION_REDEFINE_19C` in test environment
- [ ] Test basic RANGE partitioning conversion
- [ ] Test basic LIST partitioning conversion
- [ ] Test HASH partitioning conversion (if used)
- [ ] Test composite partitioning conversion (if used)
- [ ] Test AUTO_LIST partitioning (19c feature)
- [ ] Test HASH-composite partitioning (19c feature)
- [ ] Verify online conversion capability detection
- [ ] Verify offline conversion works
- [ ] Test with tables that have:
  - [ ] Primary keys
  - [ ] No primary key (ROWID-based)
  - [ ] Foreign keys
  - [ ] Multiple indexes
  - [ ] Triggers
  - [ ] Constraints
- [ ] Verify data integrity after conversion
- [ ] Verify index functionality
- [ ] Verify constraint functionality
- [ ] Test cleanup_object_names procedure
- [ ] Review all log entries
- [ ] Performance test on large table
- [ ] Test parallel processing options
- [ ] Verify rollback/cleanup on failure

---

## Common Migration Issues

### Issue 1: Different Interface

**Problem**: Old code expects `partition_object%ROWTYPE`

**Solution**: Extract values and build new structures
```sql
-- Old structure
v_obj_def partition_object%ROWTYPE;

-- New structure
v_partition_spec partition_redefine_19c.t_partition_spec;
v_partition_spec.partition_type := v_obj_def.partition_technique;
v_partition_spec.partition_key := v_obj_def.partition_key;
-- etc.
```

### Issue 2: Missing Options

**Problem**: Old code has no options, new code expects them

**Solution**: Use defaults or create helper function
```sql
-- Create wrapper function
FUNCTION convert_with_defaults(
  owner_in      VARCHAR2,
  table_name_in VARCHAR2
) RETURN BOOLEAN IS
  v_options partition_redefine_19c.t_conversion_options;
BEGIN
  -- Set defaults
  v_options.strategy := 'ONLINE';
  v_options.enable_parallel := TRUE;
  -- etc.
  
  RETURN partition_redefine_19c.convert_to_single_level_partition(
    owner_in => owner_in,
    table_name_in => table_name_in,
    options_in => v_options,
    -- ... other params
  );
END;
```

### Issue 3: Different Return Semantics

**Problem**: Old package raises exceptions, new returns BOOLEAN

**Solution**: Check return value and raise if needed
```sql
IF NOT partition_redefine_19c.convert_to_single_level_partition(...) THEN
  RAISE_APPLICATION_ERROR(-20001, 'Conversion failed - check logs');
END IF;
```

---

## Rollback Plan

If migration causes issues:

### Immediate Rollback

1. **If conversion in progress:**
   ```sql
   -- The _OLD table still exists
   -- Rename back
   ALTER TABLE my_table RENAME TO my_table_failed;
   ALTER TABLE my_table_old RENAME TO my_table;
   ```

2. **If conversion complete but issues found:**
   ```sql
   -- Old table should still exist as my_table_old
   DROP TABLE my_table;
   ALTER TABLE my_table_old RENAME TO my_table;
   ```

### Long-term Rollback

1. Uninstall new package:
   ```sql
   DROP PACKAGE partition_redefine_19c;
   ```

2. Continue using old package:
   ```sql
   -- Old package still works
   partition_redefine.redefine_object(...);
   ```

---

## Support and Resources

### Documentation
- **New Package**: [README_19C.md](README_19C.md)
- **Quick Reference**: [QUICK_REFERENCE_19C.md](QUICK_REFERENCE_19C.md)
- **Examples**: [examples_19c.sql](examples_19c.sql)
- **Main README**: [README.md](README.md)

### Logging
```sql
-- Check new package logs
SELECT * FROM log_admin.log_entry
 WHERE module_name = 'PARTITION_REDEFINE_19C'
 ORDER BY log_timestamp DESC;

-- Check old package logs
SELECT * FROM log_admin.log_entry
 WHERE module_name = 'PARTITION_REDEFINE'
 ORDER BY log_timestamp DESC;
```

### Oracle Documentation
- Oracle Database VLDB and Partitioning Guide 19c
- Oracle Database PL/SQL Packages and Types Reference 19c
- Oracle Database Administrator's Guide 19c

---

## Conclusion

The new `PARTITION_REDEFINE_19C` package provides:
- Modern Oracle 19c features
- Better control and flexibility
- Improved error handling
- Enhanced performance options

Migration is straightforward but requires:
- Testing in non-production first
- Understanding of new interface
- Awareness of new capabilities

**Recommendation**: Use side-by-side strategy for low-risk migration.

---

**Version**: 1.0.0  
**Last Updated**: 2024  
**Compatibility**: Oracle 19c and higher
