/*******************************************************************************
* Oracle 19c Partition Handler - Usage Examples
*
* This script demonstrates the new Oracle 19c partition features including:
* - AUTO_LIST partitioning
* - HASH-based composite partitioning
* - Table conversion operations
* - Online vs offline conversion
*
* Requirements:
* - Oracle Database 19c or higher
* - partition_redefine_19c package installed
* - Appropriate privileges (CREATE TABLE, ALTER TABLE, etc.)
*
* Author: Oracle Partition Handler Team
* Version: 1.0.0
*******************************************************************************/

-- =============================================================================
-- EXAMPLE 1: Convert Regular Table to AUTO_LIST Partitioning
-- =============================================================================

-- Create a sample non-partitioned table
CREATE TABLE sales_by_region (
    sale_id       NUMBER PRIMARY KEY,
    region_code   VARCHAR2(10) NOT NULL,
    sale_date     DATE NOT NULL,
    amount        NUMBER(10,2),
    customer_name VARCHAR2(100)
) TABLESPACE users;

-- Insert sample data
INSERT INTO sales_by_region VALUES (1, 'WEST', SYSDATE-10, 1500.00, 'Customer A');
INSERT INTO sales_by_region VALUES (2, 'EAST', SYSDATE-9, 2300.50, 'Customer B');
INSERT INTO sales_by_region VALUES (3, 'WEST', SYSDATE-8, 1800.75, 'Customer C');
INSERT INTO sales_by_region VALUES (4, 'NORTH', SYSDATE-7, 3200.00, 'Customer D');
INSERT INTO sales_by_region VALUES (5, 'SOUTH', SYSDATE-6, 2700.25, 'Customer E');
COMMIT;

-- Convert to AUTO_LIST partitioning
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Example 1: Converting to AUTO_LIST Partitioning ===');
  
  -- Define partition specification for AUTO_LIST
  v_partition_spec.partition_type := 'AUTO_LIST';
  v_partition_spec.partition_key := 'REGION_CODE';
  v_partition_spec.subpartition_type := NULL;
  v_partition_spec.subpartition_key := NULL;
  v_partition_spec.is_composite := FALSE;
  v_partition_spec.online_capable := TRUE;
  v_partition_spec.requires_pk := TRUE;
  
  -- Define initial partitions (AUTO_LIST will create more as needed)
  v_part_defs(1).partition_name := 'P_WEST';
  v_part_defs(1).high_value := '''WEST''';
  v_part_defs(1).tablespace_name := 'USERS';
  v_part_defs(1).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(1).partition_tech_id := partition_constants.c_par_tech_auto_list_id;
  
  v_part_defs(2).partition_name := 'P_EAST';
  v_part_defs(2).high_value := '''EAST''';
  v_part_defs(2).tablespace_name := 'USERS';
  v_part_defs(2).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(2).partition_tech_id := partition_constants.c_par_tech_auto_list_id;
  
  -- Configure conversion options for online conversion
  v_options.strategy := partition_redefine_19c.c_strategy_online;
  v_options.interim_suffix := '_NEW';
  v_options.old_suffix := '_OLD';
  v_options.copy_constraints := TRUE;
  v_options.copy_indexes := TRUE;
  v_options.copy_triggers := TRUE;
  v_options.validate_constraints := TRUE;
  v_options.enable_parallel := FALSE;
  
  -- Check if online conversion is possible
  IF partition_redefine_19c.is_online_conversion_capable(
       owner_in       => USER,
       table_name_in  => 'SALES_BY_REGION',
       partition_spec => v_partition_spec) THEN
    DBMS_OUTPUT.PUT_LINE('Online conversion is supported for this table');
  ELSE
    DBMS_OUTPUT.PUT_LINE('WARNING: Online conversion not supported, switching to offline');
    v_options.strategy := partition_redefine_19c.c_strategy_offline;
  END IF;
  
  -- Execute conversion
  DBMS_OUTPUT.PUT_LINE('Starting conversion...');
  v_success := partition_redefine_19c.convert_to_single_level_partition(
    owner_in       => USER,
    table_name_in  => 'SALES_BY_REGION',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF v_success THEN
    DBMS_OUTPUT.PUT_LINE('SUCCESS: Table converted to AUTO_LIST partitioning');
    
    -- Clean up object names (remove _NEW suffix)
    partition_redefine_19c.cleanup_object_names(
      owner_in      => USER,
      table_name_in => 'SALES_BY_REGION'
    );
    DBMS_OUTPUT.PUT_LINE('Object names cleaned up');
  ELSE
    DBMS_OUTPUT.PUT_LINE('ERROR: Conversion failed - check logs');
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/

-- Verify the conversion
SELECT table_name, partitioning_type, autolist 
  FROM user_part_tables 
 WHERE table_name = 'SALES_BY_REGION';

SELECT partition_name, high_value 
  FROM user_tab_partitions 
 WHERE table_name = 'SALES_BY_REGION';

-- Test AUTO_LIST by inserting a new region
INSERT INTO sales_by_region VALUES (6, 'CENTRAL', SYSDATE, 4500.00, 'Customer F');
COMMIT;

-- Check if new partition was automatically created
SELECT partition_name, high_value 
  FROM user_tab_partitions 
 WHERE table_name = 'SALES_BY_REGION'
 ORDER BY partition_position;

-- =============================================================================
-- EXAMPLE 2: Convert Regular Table to HASH-RANGE Composite Partitioning
-- =============================================================================

-- Create a sample non-partitioned table
CREATE TABLE customer_orders (
    order_id      NUMBER PRIMARY KEY,
    customer_id   NUMBER NOT NULL,
    order_date    DATE NOT NULL,
    order_amount  NUMBER(12,2),
    status        VARCHAR2(20)
) TABLESPACE users;

-- Insert sample data
BEGIN
  FOR i IN 1..100 LOOP
    INSERT INTO customer_orders VALUES (
      i,
      MOD(i, 10) + 1,  -- customer_id 1-10
      SYSDATE - MOD(i, 365),  -- dates in last year
      ROUND(DBMS_RANDOM.VALUE(100, 10000), 2),
      CASE MOD(i, 3) WHEN 0 THEN 'SHIPPED' WHEN 1 THEN 'PENDING' ELSE 'DELIVERED' END
    );
  END LOOP;
  COMMIT;
END;
/

-- Convert to HASH-RANGE composite partitioning
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
  v_idx            PLS_INTEGER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Example 2: Converting to HASH-RANGE Composite Partitioning ===');
  
  -- Define composite partition specification
  v_partition_spec.partition_type := 'HASH';
  v_partition_spec.partition_key := 'CUSTOMER_ID';
  v_partition_spec.subpartition_type := 'RANGE';
  v_partition_spec.subpartition_key := 'ORDER_DATE';
  v_partition_spec.is_composite := TRUE;
  v_partition_spec.online_capable := TRUE;
  v_partition_spec.requires_pk := TRUE;
  
  -- Define 2 hash partitions, each with 4 range subpartitions
  -- Partition 1 (hash)
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_HASH_1';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_hash_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Subpartitions for partition 1
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q1';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q2';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-07-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q3';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-10-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q4';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2024-01-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Partition 2 (hash) - same subpartitions
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_HASH_2';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_hash_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q1';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-04-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q2';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-07-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q3';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-10-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'SP_2023_Q4';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2024-01-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Configure for online conversion with parallel processing
  v_options.strategy := partition_redefine_19c.c_strategy_online;
  v_options.enable_parallel := TRUE;
  v_options.parallel_degree := 4;
  v_options.copy_constraints := TRUE;
  v_options.copy_indexes := TRUE;
  v_options.validate_constraints := TRUE;
  
  -- Execute conversion
  DBMS_OUTPUT.PUT_LINE('Starting HASH-RANGE composite conversion...');
  v_success := partition_redefine_19c.convert_to_composite_partition(
    owner_in       => USER,
    table_name_in  => 'CUSTOMER_ORDERS',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF v_success THEN
    DBMS_OUTPUT.PUT_LINE('SUCCESS: Table converted to HASH-RANGE composite partitioning');
    
    -- Clean up object names
    partition_redefine_19c.cleanup_object_names(
      owner_in      => USER,
      table_name_in => 'CUSTOMER_ORDERS'
    );
    DBMS_OUTPUT.PUT_LINE('Object names cleaned up');
  ELSE
    DBMS_OUTPUT.PUT_LINE('ERROR: Conversion failed - check logs');
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/

-- Verify the composite partitioning
SELECT table_name, partitioning_type, subpartitioning_type 
  FROM user_part_tables 
 WHERE table_name = 'CUSTOMER_ORDERS';

SELECT partition_name, subpartition_count 
  FROM user_tab_partitions 
 WHERE table_name = 'CUSTOMER_ORDERS';

SELECT partition_name, subpartition_name, high_value 
  FROM user_tab_subpartitions 
 WHERE table_name = 'CUSTOMER_ORDERS'
 ORDER BY subpartition_position;

-- =============================================================================
-- EXAMPLE 3: Convert Single-Level to Composite Partitioning
-- =============================================================================

-- Create a sample range-partitioned table
CREATE TABLE transaction_log (
    txn_id        NUMBER PRIMARY KEY,
    txn_date      DATE NOT NULL,
    account_id    NUMBER NOT NULL,
    amount        NUMBER(12,2),
    txn_type      VARCHAR2(20)
)
PARTITION BY RANGE (txn_date) (
    PARTITION p_2023_q1 VALUES LESS THAN (TO_DATE('2023-04-01', 'YYYY-MM-DD')),
    PARTITION p_2023_q2 VALUES LESS THAN (TO_DATE('2023-07-01', 'YYYY-MM-DD')),
    PARTITION p_2023_q3 VALUES LESS THAN (TO_DATE('2023-10-01', 'YYYY-MM-DD')),
    PARTITION p_2023_q4 VALUES LESS THAN (TO_DATE('2024-01-01', 'YYYY-MM-DD'))
);

-- Insert sample data
BEGIN
  FOR i IN 1..50 LOOP
    INSERT INTO transaction_log VALUES (
      i,
      TO_DATE('2023-01-01', 'YYYY-MM-DD') + MOD(i, 365),
      MOD(i, 100) + 1,
      ROUND(DBMS_RANDOM.VALUE(10, 5000), 2),
      CASE MOD(i, 3) WHEN 0 THEN 'DEBIT' WHEN 1 THEN 'CREDIT' ELSE 'TRANSFER' END
    );
  END LOOP;
  COMMIT;
END;
/

-- Convert to RANGE-HASH composite partitioning
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_options        partition_redefine_19c.t_conversion_options;
  v_success        BOOLEAN;
  v_idx            PLS_INTEGER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Example 3: Converting Single-Level to Composite Partitioning ===');
  
  -- Define new composite partition specification
  v_partition_spec.partition_type := 'RANGE';
  v_partition_spec.partition_key := 'TXN_DATE';
  v_partition_spec.subpartition_type := 'HASH';
  v_partition_spec.subpartition_key := 'ACCOUNT_ID';
  v_partition_spec.is_composite := TRUE;
  v_partition_spec.online_capable := TRUE;
  v_partition_spec.requires_pk := TRUE;
  
  -- Define range partitions with hash subpartitions
  -- We'll create 2 quarterly partitions, each with 4 hash subpartitions
  
  -- Q3 2023 with 4 hash subpartitions
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_2023_Q3';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2023-10-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Hash subpartitions for Q3
  FOR i IN 1..4 LOOP
    v_idx := v_idx + 1;
    v_part_defs(v_idx).partition_name := 'SP_HASH_' || i;
    v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
    v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_hash_id;
    v_part_defs(v_idx).tablespace_name := 'USERS';
  END LOOP;
  
  -- Q4 2023 with 4 hash subpartitions
  v_idx := v_idx + 1;
  v_part_defs(v_idx).partition_name := 'P_2023_Q4';
  v_part_defs(v_idx).high_value := 'TO_DATE(''2024-01-01'', ''YYYY-MM-DD'')';
  v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_partition_id;
  v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_range_id;
  v_part_defs(v_idx).tablespace_name := 'USERS';
  
  -- Hash subpartitions for Q4
  FOR i IN 1..4 LOOP
    v_idx := v_idx + 1;
    v_part_defs(v_idx).partition_name := 'SP_HASH_' || i;
    v_part_defs(v_idx).partition_type_id := partition_constants.c_par_type_subpartition_id;
    v_part_defs(v_idx).partition_tech_id := partition_constants.c_par_tech_hash_id;
    v_part_defs(v_idx).tablespace_name := 'USERS';
  END LOOP;
  
  -- Configure conversion options
  v_options.strategy := partition_redefine_19c.c_strategy_online;
  v_options.copy_constraints := TRUE;
  v_options.copy_indexes := TRUE;
  v_options.validate_constraints := TRUE;
  
  -- Execute conversion
  DBMS_OUTPUT.PUT_LINE('Converting single-level to composite partitioning...');
  v_success := partition_redefine_19c.convert_single_to_composite(
    owner_in       => USER,
    table_name_in  => 'TRANSACTION_LOG',
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs,
    options_in     => v_options
  );
  
  IF v_success THEN
    DBMS_OUTPUT.PUT_LINE('SUCCESS: Table converted to RANGE-HASH composite partitioning');
    
    partition_redefine_19c.cleanup_object_names(
      owner_in      => USER,
      table_name_in => 'TRANSACTION_LOG'
    );
  ELSE
    DBMS_OUTPUT.PUT_LINE('ERROR: Conversion failed - check logs');
  END IF;
  
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('ERROR: ' || SQLERRM);
    RAISE;
END;
/

-- Verify the composite partitioning
SELECT table_name, partitioning_type, subpartitioning_type 
  FROM user_part_tables 
 WHERE table_name = 'TRANSACTION_LOG';

-- =============================================================================
-- EXAMPLE 4: Generate Partition DDL Without Conversion
-- =============================================================================

-- This example shows how to generate partition DDL for preview
DECLARE
  v_partition_spec partition_redefine_19c.t_partition_spec;
  v_part_defs      partition_types.t_partition_def_table;
  v_ddl            CLOB;
BEGIN
  DBMS_OUTPUT.PUT_LINE('=== Example 4: Generate Partition DDL ===');
  
  -- Define partition specification
  v_partition_spec.partition_type := 'AUTO_LIST';
  v_partition_spec.partition_key := 'REGION_CODE';
  v_partition_spec.is_composite := FALSE;
  
  -- Define partitions
  v_part_defs(1).partition_name := 'P_NORTH';
  v_part_defs(1).high_value := '''NORTH''';
  v_part_defs(1).tablespace_name := 'USERS';
  
  v_part_defs(2).partition_name := 'P_SOUTH';
  v_part_defs(2).high_value := '''SOUTH''';
  v_part_defs(2).tablespace_name := 'USERS';
  
  -- Generate DDL
  v_ddl := partition_redefine_19c.generate_partition_ddl_19c(
    partition_spec => v_partition_spec,
    part_defs_in   => v_part_defs
  );
  
  -- Output the generated DDL
  DBMS_OUTPUT.PUT_LINE('Generated Partition DDL:');
  DBMS_OUTPUT.PUT_LINE(v_ddl);
  
END;
/

-- =============================================================================
-- CLEANUP (Optional)
-- =============================================================================

/*
-- Uncomment to drop the example tables
DROP TABLE sales_by_region PURGE;
DROP TABLE customer_orders PURGE;
DROP TABLE transaction_log PURGE;

-- Also drop the _OLD tables if they exist
DROP TABLE sales_by_region_old PURGE;
DROP TABLE customer_orders_old PURGE;
DROP TABLE transaction_log_old PURGE;
*/

-- =============================================================================
-- SUMMARY
-- =============================================================================

PROMPT
PROMPT ========================================================================
PROMPT Oracle 19c Partition Handler Examples Completed
PROMPT ========================================================================
PROMPT
PROMPT Examples demonstrated:
PROMPT 1. Convert regular table to AUTO_LIST partitioning
PROMPT 2. Convert regular table to HASH-RANGE composite partitioning
PROMPT 3. Convert single-level to RANGE-HASH composite partitioning
PROMPT 4. Generate partition DDL for preview
PROMPT
PROMPT Key features showcased:
PROMPT - AUTO_LIST automatic partition creation
PROMPT - HASH-based composite partitioning (19c feature)
PROMPT - Online vs offline conversion strategies
PROMPT - Parallel processing support
PROMPT - Incremental sync mechanism
PROMPT - Object name cleanup (_NEW suffix removal)
PROMPT
PROMPT For more information, see README_19C.md
PROMPT ========================================================================
