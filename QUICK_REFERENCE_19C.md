# Oracle 19c Partition Handler - Quick Reference

## Installation

```sql
-- Install the new 19c package (after installing base packages)
@@partition_redefine_19c.pck
```

## Partition Technique IDs

| ID | Name | Description | Oracle Version |
|----|------|-------------|----------------|
| 1 | LIST | Discrete value partitioning | All |
| 2 | RANGE | Range-based partitioning | All |
| 3 | HASH | Hash-based partitioning | All |
| 4 | INTERVAL | Automatic range partitioning | 11g+ |
| 5 | REFERENCE | Parent-child partitioning | 11g+ |
| 6 | AUTO_LIST | Automatic LIST partition | **19c+** |

## Composite Partitioning Support Matrix

### Traditional (All Versions)
- RANGE-RANGE
- RANGE-HASH
- RANGE-LIST
- LIST-RANGE
- LIST-HASH
- LIST-LIST

### Oracle 19c Enhanced
- **HASH-RANGE** ⭐
- **HASH-HASH** ⭐
- **HASH-LIST** ⭐

## Quick Start Examples

### 1. Convert to AUTO_LIST (Simplest)

```sql
DECLARE
  v_spec partition_redefine_19c.t_partition_spec;
  v_defs partition_types.t_partition_def_table;
  v_success BOOLEAN;
BEGIN
  -- Setup
  v_spec.partition_type := 'AUTO_LIST';
  v_spec.partition_key := 'STATUS';
  v_spec.is_composite := FALSE;
  
  -- Define initial partition
  v_defs(1).partition_name := 'P_ACTIVE';
  v_defs(1).high_value := '''ACTIVE''';
  v_defs(1).tablespace_name := 'USERS';
  v_defs(1).partition_type_id := 1; -- PARTITION
  
  -- Convert
  v_success := partition_redefine_19c.convert_to_single_level_partition(
    owner_in       => USER,
    table_name_in  => 'MY_TABLE',
    partition_spec => v_spec,
    part_defs_in   => v_defs
  );
END;
/
```

### 2. Convert to HASH-RANGE Composite

```sql
DECLARE
  v_spec partition_redefine_19c.t_partition_spec;
  v_defs partition_types.t_partition_def_table;
  v_success BOOLEAN;
BEGIN
  -- Setup composite spec
  v_spec.partition_type := 'HASH';
  v_spec.partition_key := 'CUSTOMER_ID';
  v_spec.subpartition_type := 'RANGE';
  v_spec.subpartition_key := 'ORDER_DATE';
  v_spec.is_composite := TRUE;
  
  -- Partition 1
  v_defs(1).partition_name := 'P_HASH_1';
  v_defs(1).partition_type_id := 1; -- PARTITION
  
  -- Subpartition 1-1
  v_defs(2).partition_name := 'SP_2024_Q1';
  v_defs(2).high_value := 'TO_DATE(''2024-04-01'', ''YYYY-MM-DD'')';
  v_defs(2).partition_type_id := 2; -- SUBPARTITION
  
  -- (Add more partitions/subpartitions as needed)
  
  -- Convert
  v_success := partition_redefine_19c.convert_to_composite_partition(
    owner_in       => USER,
    table_name_in  => 'MY_TABLE',
    partition_spec => v_spec,
    part_defs_in   => v_defs
  );
END;
/
```

### 3. Check Online Capability First

```sql
DECLARE
  v_spec partition_redefine_19c.t_partition_spec;
  v_can_online BOOLEAN;
BEGIN
  v_spec.partition_type := 'RANGE';
  v_spec.partition_key := 'CREATED_DATE';
  v_spec.is_composite := FALSE;
  
  v_can_online := partition_redefine_19c.is_online_conversion_capable(
    owner_in       => USER,
    table_name_in  => 'MY_TABLE',
    partition_spec => v_spec
  );
  
  IF v_can_online THEN
    DBMS_OUTPUT.PUT_LINE('Online conversion supported');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Offline conversion required');
  END IF;
END;
/
```

## Conversion Options

```sql
DECLARE
  v_options partition_redefine_19c.t_conversion_options;
BEGIN
  -- Full configuration
  v_options.strategy := 'ONLINE';              -- or 'OFFLINE'
  v_options.interim_suffix := '_NEW';          -- suffix for temp table
  v_options.old_suffix := '_OLD';              -- suffix for old table
  v_options.copy_constraints := TRUE;          -- copy constraints
  v_options.copy_indexes := TRUE;              -- copy indexes
  v_options.copy_triggers := TRUE;             -- copy triggers
  v_options.validate_constraints := TRUE;      -- enable constraints after
  v_options.max_sync_iterations := 10;         -- max sync loops
  v_options.enable_parallel := TRUE;           -- use parallel DML
  v_options.parallel_degree := 4;              -- parallel degree
  
  -- Use in conversion
  -- v_success := partition_redefine_19c.convert_to_...(options_in => v_options);
END;
/
```

## Post-Conversion Tasks

### 1. Verify Conversion

```sql
-- Check partitioning type
SELECT table_name, partitioning_type, subpartitioning_type, autolist
  FROM user_part_tables
 WHERE table_name = 'MY_TABLE';

-- Check partitions
SELECT partition_name, high_value, tablespace_name
  FROM user_tab_partitions
 WHERE table_name = 'MY_TABLE'
 ORDER BY partition_position;

-- For composite partitioning
SELECT partition_name, subpartition_name, high_value
  FROM user_tab_subpartitions
 WHERE table_name = 'MY_TABLE'
 ORDER BY subpartition_position;
```

### 2. Clean Up Object Names

```sql
-- Remove _NEW suffixes from constraints and indexes
BEGIN
  partition_redefine_19c.cleanup_object_names(
    owner_in      => USER,
    table_name_in => 'MY_TABLE'
  );
END;
/
```

### 3. Drop Old Table (After Verification)

```sql
DROP TABLE my_table_old PURGE;
```

## Troubleshooting

### Check Logs

```sql
SELECT log_timestamp, log_level, message
  FROM log_admin.log_entry
 WHERE module_name = 'PARTITION_REDEFINE_19C'
   AND log_timestamp > SYSTIMESTAMP - INTERVAL '1' HOUR
 ORDER BY log_timestamp DESC;
```

### Common Issues

| Issue | Solution |
|-------|----------|
| "Online not supported" | Add primary key or use `strategy := 'OFFLINE'` |
| "Insufficient storage" | Free up space (2x table size needed) |
| "Constraint validation failed" | Fix data or use `validate_constraints := FALSE` |
| "Sync timeout" | Reduce activity or increase `max_sync_iterations` |

## Performance Tips

### For Large Tables

```sql
v_options.enable_parallel := TRUE;
v_options.parallel_degree := 8;  -- Match CPU count
v_options.strategy := 'ONLINE';  -- If PK exists
```

### For Small Tables

```sql
v_options.strategy := 'OFFLINE';  -- Faster for small tables
v_options.enable_parallel := FALSE;
```

### For Active Tables

```sql
v_options.strategy := 'ONLINE';
v_options.max_sync_iterations := 20;  -- Allow more sync cycles
-- Schedule during low-activity period
```

## Best Practices Checklist

- [ ] Verify table has primary key for online conversion
- [ ] Check available storage (need 2x table size)
- [ ] Test on development environment first
- [ ] Schedule during low-activity period
- [ ] Monitor sync iterations if using online
- [ ] Verify data integrity after conversion
- [ ] Keep `_OLD` table until fully verified
- [ ] Clean up object names after verification
- [ ] Update statistics on new partitioned table
- [ ] Test application queries on new structure

## When to Use Each Partition Type

### AUTO_LIST
- ✅ Categorical data with unknown/evolving values
- ✅ New values added frequently
- ✅ Don't want manual partition maintenance
- ❌ Very high cardinality (thousands of values)

### HASH-RANGE Composite
- ✅ High transaction volume + time-based queries
- ✅ Need even distribution + partition pruning
- ✅ Parallel processing is important
- ❌ Queries don't benefit from hash distribution

### HASH-HASH Composite
- ✅ Maximum parallelism needed
- ✅ Even distribution is critical
- ✅ No time-based access patterns
- ❌ Need partition pruning by value

### HASH-LIST Composite
- ✅ Multi-tenant systems
- ✅ Load balancing + regional segregation
- ✅ Even distribution with category isolation
- ❌ Simple single-level partitioning sufficient

## Migration Path from Legacy Package

```sql
-- Old way (partition_redefine.pck)
BEGIN
  partition_redefine.redefine_object(...);
END;
/

-- New way (partition_redefine_19c.pck)
-- More control, 19c features, online/offline choice
BEGIN
  v_success := partition_redefine_19c.convert_to_single_level_partition(...);
END;
/
```

## Resources

- **Full Documentation**: [README_19C.md](README_19C.md)
- **Examples**: [examples_19c.sql](examples_19c.sql)
- **Main README**: [README.md](README.md)
- **Oracle Docs**: Oracle Database VLDB and Partitioning Guide 19c

## Support

For issues or questions:
1. Check logs using `log_admin.log_entry`
2. Review [README_19C.md](README_19C.md) troubleshooting section
3. Test in development environment
4. Review Oracle documentation for partition-specific errors

---

**Version**: 1.0.0  
**Package**: PARTITION_REDEFINE_19C  
**Requirements**: Oracle Database 19c or higher
