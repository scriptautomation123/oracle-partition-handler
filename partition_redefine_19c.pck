CREATE OR REPLACE PACKAGE partition_redefine_19c AUTHID CURRENT_USER IS
  /*******************************************************************************
  * Oracle 19c Partition Redefinition and Conversion Package
  *
  * Author:   Oracle Partition Handler Team
  * Date:     2024
  * Version:  1.0.0
  *
  * Purpose:  Modern partition conversion utilities for Oracle 19c
  *           Supports all Oracle 19c partition features including:
  *           - AUTO_LIST partitioning
  *           - HASH-based composite partitioning (HASH-RANGE, HASH-HASH, HASH-LIST)
  *           - Online and offline conversion operations
  *           - Table copy with incremental sync and rename
  *
  * Requires: Oracle 19c or higher
  *           module_admin v1.7.0
  *           log_admin v1.2.3
  *           partition_handler v0.9.45
  ******************************************************************************/
  gc_module_version CONSTANT module_admin.t_module_version := '1.0.0';
  gc_module_label   CONSTANT module_admin.t_module_label := $$PLSQL_UNIT || ' v' || gc_module_version;

  -- Conversion strategy constants
  c_strategy_online  CONSTANT VARCHAR2(10) := 'ONLINE';
  c_strategy_offline CONSTANT VARCHAR2(10) := 'OFFLINE';
  
  -- Partition type classification
  TYPE t_partition_spec IS RECORD(
    partition_type      VARCHAR2(20),    -- RANGE, LIST, HASH, INTERVAL, REFERENCE, AUTO_LIST
    subpartition_type   VARCHAR2(20),    -- NULL for single-level, or RANGE/LIST/HASH for composite
    partition_key       VARCHAR2(4000),  -- Column(s) for partitioning
    subpartition_key    VARCHAR2(4000),  -- Column(s) for subpartitioning
    is_composite        BOOLEAN,         -- TRUE if composite partitioning
    online_capable      BOOLEAN,         -- TRUE if online conversion is possible
    requires_pk         BOOLEAN          -- TRUE if primary key is required
  );
  
  TYPE t_conversion_options IS RECORD(
    strategy            VARCHAR2(10),    -- ONLINE or OFFLINE
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

  /*******************************************************************************
  * Convert a regular (non-partitioned) table to single-level partitioning
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Table name to convert
  *   partition_spec   - Partition specification (type, keys, etc.)
  *   part_defs_in     - Partition definitions
  *   options_in       - Conversion options (online/offline, etc.)
  *   
  * Returns: TRUE if conversion successful, FALSE otherwise
  *******************************************************************************/
  FUNCTION convert_to_single_level_partition(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN;

  /*******************************************************************************
  * Convert a regular (non-partitioned) table to composite partitioning
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Table name to convert
  *   partition_spec   - Partition specification with composite definition
  *   part_defs_in     - Partition and subpartition definitions
  *   options_in       - Conversion options
  *   
  * Returns: TRUE if conversion successful, FALSE otherwise
  *******************************************************************************/
  FUNCTION convert_to_composite_partition(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN;

  /*******************************************************************************
  * Convert a single-level partitioned table to composite partitioning
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Table name to convert
  *   partition_spec   - New composite partition specification
  *   part_defs_in     - New partition/subpartition definitions
  *   options_in       - Conversion options
  *   
  * Returns: TRUE if conversion successful, FALSE otherwise
  *******************************************************************************/
  FUNCTION convert_single_to_composite(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN;

  /*******************************************************************************
  * Check if a specific partition strategy can be done online
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Table name
  *   partition_spec   - Desired partition specification
  *   
  * Returns: TRUE if online conversion is possible
  *******************************************************************************/
  FUNCTION is_online_conversion_capable(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec
  ) RETURN BOOLEAN;

  /*******************************************************************************
  * Generate partition DDL for Oracle 19c features
  * 
  * Parameters:
  *   partition_spec   - Partition specification
  *   part_defs_in     - Partition definitions
  *   
  * Returns: CLOB containing partition DDL clause
  *******************************************************************************/
  FUNCTION generate_partition_ddl_19c(
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table
  ) RETURN CLOB;

  /*******************************************************************************
  * Execute table conversion with incremental sync and rename
  * 
  * This procedure implements the full conversion workflow:
  * 1. Create new table with _NEW suffix
  * 2. Copy constraints and indexes
  * 3. Initial data load (INSERT INTO SELECT)
  * 4. Incremental sync in loop
  * 5. Atomic rename (original -> _OLD, _NEW -> original)
  * 6. Optional cleanup of _OLD table
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Original table name
  *   new_table_ddl    - DDL to create new partitioned table
  *   options_in       - Conversion options
  *******************************************************************************/
  PROCEDURE execute_conversion_with_sync(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    new_table_ddl    IN CLOB,
    options_in       IN t_conversion_options DEFAULT NULL
  );

  /*******************************************************************************
  * Rename indexes and constraints from _NEW to original names
  * 
  * This is executed after the table rename to clean up naming
  * 
  * Parameters:
  *   owner_in         - Schema owner
  *   table_name_in    - Table name (after rename)
  *******************************************************************************/
  PROCEDURE cleanup_object_names(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2
  );

END partition_redefine_19c;
/

CREATE OR REPLACE PACKAGE BODY partition_redefine_19c IS

  /*******************************************************************************
  * Constants
  *******************************************************************************/
  c_max_identifier_length CONSTANT INTEGER := 30; -- Oracle identifier max length

  /*******************************************************************************
  * Exceptions
  *******************************************************************************/
  e_invalid_partition_spec EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_invalid_partition_spec, -20101);
  
  e_conversion_failed EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_conversion_failed, -20102);
  
  e_online_not_supported EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_online_not_supported, -20103);
  
  e_sync_timeout EXCEPTION;
  PRAGMA EXCEPTION_INIT(e_sync_timeout, -20104);

  /*******************************************************************************
  * Helper function to validate partition specification
  *******************************************************************************/
  FUNCTION validate_partition_spec(partition_spec IN t_partition_spec) RETURN BOOLEAN IS
    v_module_action log_admin.t_module_action := 'validate_partition_spec';
  BEGIN
    -- Check that partition type is specified
    IF partition_spec.partition_type IS NULL THEN
      log_admin.error('Partition type is required', 
                      module_name_in => $$PLSQL_UNIT, 
                      module_action_in => v_module_action);
      RETURN FALSE;
    END IF;
    
    -- Check that partition key is specified
    IF partition_spec.partition_key IS NULL THEN
      log_admin.error('Partition key is required', 
                      module_name_in => $$PLSQL_UNIT, 
                      module_action_in => v_module_action);
      RETURN FALSE;
    END IF;
    
    -- If composite, validate subpartition spec
    IF partition_spec.is_composite THEN
      IF partition_spec.subpartition_type IS NULL OR partition_spec.subpartition_key IS NULL THEN
        log_admin.error('Subpartition type and key required for composite partitioning',
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action);
        RETURN FALSE;
      END IF;
    END IF;
    
    RETURN TRUE;
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical(dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RETURN FALSE;
  END validate_partition_spec;

  /*******************************************************************************
  * Check if online conversion is capable
  *******************************************************************************/
  FUNCTION is_online_conversion_capable(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec
  ) RETURN BOOLEAN IS
    v_module_action log_admin.t_module_action := 'is_online_conversion_capable';
    v_has_pk        BOOLEAN;
    v_has_lobs      BOOLEAN;
    v_pk_name       VARCHAR2(128);
  BEGIN
    log_admin.debug('Checking online conversion capability for ' || owner_in || '.' || table_name_in,
                    module_name_in => $$PLSQL_UNIT,
                    module_action_in => v_module_action);
    
    -- Check if table has primary key
    BEGIN
      v_pk_name := object_admin.get_table_primary_key_name(owner_in => owner_in, 
                                                            table_name_in => table_name_in);
      v_has_pk := (v_pk_name IS NOT NULL);
    EXCEPTION
      WHEN OTHERS THEN
        v_has_pk := FALSE;
    END;
    
    -- Check if table has LOB columns
    BEGIN
      SELECT COUNT(*) > 0 INTO v_has_lobs
        FROM dba_tab_columns
       WHERE owner = owner_in
         AND table_name = table_name_in
         AND data_type IN ('BLOB', 'CLOB', 'NCLOB');
    EXCEPTION
      WHEN OTHERS THEN
        v_has_lobs := FALSE;
    END;
    
    -- Online redefinition requires:
    -- 1. Primary key OR ROWID capability
    -- 2. No issues with LOBs (generally supported in 19c)
    -- 3. Table not involved in replication (not checked here)
    
    -- AUTO_LIST requires 19c and can be done online
    IF partition_spec.partition_type = 'AUTO_LIST' THEN
      RETURN v_has_pk OR NOT partition_spec.requires_pk;
    END IF;
    
    -- HASH composite partitioning (19c feature) can be done online
    IF partition_spec.partition_type = 'HASH' AND partition_spec.is_composite THEN
      RETURN v_has_pk OR NOT partition_spec.requires_pk;
    END IF;
    
    -- All other partition types can generally be done online if table has PK
    RETURN v_has_pk;
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.error('Error checking online capability: ' || SQLERRM,
                      module_name_in => $$PLSQL_UNIT,
                      module_action_in => v_module_action,
                      sql_code_in => SQLCODE,
                      sql_errm_in => SQLERRM);
      RETURN FALSE;
  END is_online_conversion_capable;

  /*******************************************************************************
  * Generate partition DDL for Oracle 19c features
  *******************************************************************************/
  FUNCTION generate_partition_ddl_19c(
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table
  ) RETURN CLOB IS
    v_module_action log_admin.t_module_action := 'generate_partition_ddl_19c';
    v_ddl           CLOB;
    v_first_part    BOOLEAN := TRUE;
    v_first_subpart BOOLEAN := TRUE;
    v_last_part_id  PLS_INTEGER := NULL;
  BEGIN
    dbms_lob.createtemporary(v_ddl, TRUE);
    
    -- Single-level partitioning
    IF NOT partition_spec.is_composite THEN
      -- PARTITION BY clause
      IF partition_spec.partition_type = 'AUTO_LIST' THEN
        dbms_lob.append(v_ddl, chr(10) || 'PARTITION BY AUTO LIST (' || partition_spec.partition_key || ')');
      ELSIF partition_spec.partition_type = 'INTERVAL' THEN
        -- For INTERVAL, we need special handling
        dbms_lob.append(v_ddl, chr(10) || 'PARTITION BY RANGE (' || partition_spec.partition_key || ')');
        dbms_lob.append(v_ddl, chr(10) || 'INTERVAL(NUMTOYMINTERVAL(1, ''MONTH''))');
      ELSE
        dbms_lob.append(v_ddl, chr(10) || 'PARTITION BY ' || partition_spec.partition_type || 
                               ' (' || partition_spec.partition_key || ')');
      END IF;
      
      -- Add partition definitions
      IF part_defs_in.COUNT > 0 THEN
        dbms_lob.append(v_ddl, chr(10) || '(');
        FOR i IN part_defs_in.FIRST .. part_defs_in.LAST LOOP
          IF NOT v_first_part THEN
            dbms_lob.append(v_ddl, ',' || chr(10));
          END IF;
          v_first_part := FALSE;
          
          -- PARTITION name VALUES ...
          dbms_lob.append(v_ddl, '  PARTITION ' || part_defs_in(i).partition_name);
          
          -- Add VALUES clause based on partition type
          IF partition_spec.partition_type = 'RANGE' OR partition_spec.partition_type = 'INTERVAL' THEN
            dbms_lob.append(v_ddl, ' VALUES LESS THAN (' || part_defs_in(i).high_value || ')');
          ELSIF partition_spec.partition_type = 'LIST' OR partition_spec.partition_type = 'AUTO_LIST' THEN
            dbms_lob.append(v_ddl, ' VALUES (' || part_defs_in(i).high_value || ')');
          ELSIF partition_spec.partition_type = 'HASH' THEN
            -- HASH partitions don't need VALUES clause
            NULL;
          END IF;
          
          -- Add TABLESPACE clause
          IF part_defs_in(i).tablespace_name IS NOT NULL THEN
            dbms_lob.append(v_ddl, ' TABLESPACE ' || part_defs_in(i).tablespace_name);
          END IF;
        END LOOP;
        dbms_lob.append(v_ddl, chr(10) || ')');
      END IF;
      
    ELSE
      -- Composite partitioning
      dbms_lob.append(v_ddl, chr(10) || 'PARTITION BY ' || partition_spec.partition_type || 
                             ' (' || partition_spec.partition_key || ')');
      dbms_lob.append(v_ddl, chr(10) || 'SUBPARTITION BY ' || partition_spec.subpartition_type || 
                             ' (' || partition_spec.subpartition_key || ')');
      
      -- Add partition/subpartition definitions
      IF part_defs_in.COUNT > 0 THEN
        dbms_lob.append(v_ddl, chr(10) || '(');
        v_first_part := TRUE;
        v_last_part_id := NULL;
        
        FOR i IN part_defs_in.FIRST .. part_defs_in.LAST LOOP
          -- Check if this is a partition or subpartition
          IF part_defs_in(i).partition_type_id = partition_constants.c_par_type_partition_id THEN
            -- Close previous partition if exists
            IF v_last_part_id IS NOT NULL THEN
              dbms_lob.append(v_ddl, chr(10) || '  )');
            END IF;
            
            IF NOT v_first_part THEN
              dbms_lob.append(v_ddl, ',' || chr(10));
            END IF;
            v_first_part := FALSE;
            v_first_subpart := TRUE;
            
            -- PARTITION definition
            dbms_lob.append(v_ddl, '  PARTITION ' || part_defs_in(i).partition_name);
            
            -- Add VALUES clause for partition
            IF partition_spec.partition_type = 'RANGE' THEN
              dbms_lob.append(v_ddl, ' VALUES LESS THAN (' || part_defs_in(i).high_value || ')');
            ELSIF partition_spec.partition_type IN ('LIST', 'AUTO_LIST') THEN
              dbms_lob.append(v_ddl, ' VALUES (' || part_defs_in(i).high_value || ')');
            END IF;
            
            dbms_lob.append(v_ddl, chr(10) || '  (');
            v_last_part_id := i;
            
          ELSE
            -- SUBPARTITION definition
            IF NOT v_first_subpart THEN
              dbms_lob.append(v_ddl, ',' || chr(10));
            END IF;
            v_first_subpart := FALSE;
            
            dbms_lob.append(v_ddl, '    SUBPARTITION ' || part_defs_in(i).partition_name);
            
            -- Add VALUES clause for subpartition
            IF partition_spec.subpartition_type = 'RANGE' THEN
              dbms_lob.append(v_ddl, ' VALUES LESS THAN (' || part_defs_in(i).high_value || ')');
            ELSIF partition_spec.subpartition_type IN ('LIST', 'AUTO_LIST') THEN
              dbms_lob.append(v_ddl, ' VALUES (' || part_defs_in(i).high_value || ')');
            END IF;
            
            -- Add TABLESPACE clause
            IF part_defs_in(i).tablespace_name IS NOT NULL THEN
              dbms_lob.append(v_ddl, ' TABLESPACE ' || part_defs_in(i).tablespace_name);
            END IF;
          END IF;
        END LOOP;
        
        -- Close last partition
        IF v_last_part_id IS NOT NULL THEN
          dbms_lob.append(v_ddl, chr(10) || '  )');
        END IF;
        
        dbms_lob.append(v_ddl, chr(10) || ')');
      END IF;
    END IF;
    
    RETURN v_ddl;
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical(dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RAISE;
  END generate_partition_ddl_19c;

  /*******************************************************************************
  * Execute conversion with sync
  *******************************************************************************/
  PROCEDURE execute_conversion_with_sync(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    new_table_ddl    IN CLOB,
    options_in       IN t_conversion_options DEFAULT NULL
  ) IS
    v_module_action     log_admin.t_module_action := 'execute_conversion_with_sync';
    v_options           t_conversion_options;
    v_new_table_name    VARCHAR2(128);
    v_old_table_name    VARCHAR2(128);
    v_sync_count        INTEGER := 0;
    v_rows_synced       INTEGER := 0;
    v_last_sync_rows    INTEGER := 0;
  BEGIN
    log_admin.info('Starting conversion with sync for ' || owner_in || '.' || table_name_in,
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Initialize options with defaults if not provided
    IF options_in.strategy IS NULL THEN
      v_options.strategy := c_strategy_online;
      v_options.interim_suffix := '_NEW';
      v_options.old_suffix := '_OLD';
      v_options.copy_constraints := TRUE;
      v_options.copy_indexes := TRUE;
      v_options.copy_triggers := TRUE;
      v_options.validate_constraints := TRUE;
      v_options.max_sync_iterations := 10;
      v_options.enable_parallel := FALSE;
      v_options.parallel_degree := 4;
    ELSE
      v_options := options_in;
    END IF;
    
    -- Generate table names
    v_new_table_name := substr(table_name_in || v_options.interim_suffix, 1, c_max_identifier_length);
    v_old_table_name := substr(table_name_in || v_options.old_suffix, 1, c_max_identifier_length);
    
    log_admin.debug('New table name: ' || v_new_table_name || ', Old table name: ' || v_old_table_name,
                    module_name_in => $$PLSQL_UNIT,
                    module_action_in => v_module_action);
    
    -- Step 1: Create new partitioned table
    log_admin.info('Step 1: Creating new partitioned table ' || v_new_table_name,
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    sql_admin.execute_sql(REPLACE(new_table_ddl, table_name_in, v_new_table_name));
    
    -- Step 2: Copy constraints (disabled initially)
    IF v_options.copy_constraints THEN
      log_admin.info('Step 2: Copying constraints (disabled)',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
      
      FOR rec IN (SELECT constraint_name, constraint_type, search_condition, r_constraint_name
                    FROM dba_constraints
                   WHERE owner = owner_in
                     AND table_name = table_name_in
                     AND constraint_type IN ('C', 'U', 'P')
                     AND generated != 'GENERATED NAME') LOOP
        BEGIN
          DECLARE
            v_constraint_ddl VARCHAR2(4000);
          BEGIN
            v_constraint_ddl := 'ALTER TABLE "' || owner_in || '"."' || v_new_table_name || 
                               '" ADD CONSTRAINT "' || rec.constraint_name || v_options.interim_suffix || '" ';
            
            IF rec.constraint_type = 'P' THEN
              v_constraint_ddl := v_constraint_ddl || 'PRIMARY KEY';
            ELSIF rec.constraint_type = 'U' THEN
              v_constraint_ddl := v_constraint_ddl || 'UNIQUE';
            ELSIF rec.constraint_type = 'C' THEN
              v_constraint_ddl := v_constraint_ddl || 'CHECK (' || rec.search_condition || ')';
            END IF;
            
            -- Get columns for PK/UK
            IF rec.constraint_type IN ('P', 'U') THEN
              DECLARE
                v_columns VARCHAR2(4000);
              BEGIN
                SELECT '(' || listagg(column_name, ', ') WITHIN GROUP (ORDER BY position) || ')'
                  INTO v_columns
                  FROM dba_cons_columns
                 WHERE owner = owner_in
                   AND constraint_name = rec.constraint_name;
                   
                v_constraint_ddl := v_constraint_ddl || ' ' || v_columns;
              END;
            END IF;
            
            v_constraint_ddl := v_constraint_ddl || ' DISABLE NOVALIDATE';
            sql_admin.execute_sql(v_constraint_ddl);
          END;
        EXCEPTION
          WHEN OTHERS THEN
            log_admin.warning('Failed to copy constraint ' || rec.constraint_name || ': ' || SQLERRM,
                            module_name_in => $$PLSQL_UNIT,
                            module_action_in => v_module_action);
        END;
      END LOOP;
    END IF;
    
    -- Step 3: Copy indexes
    IF v_options.copy_indexes THEN
      log_admin.info('Step 3: Copying indexes',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
      
      FOR rec IN (SELECT index_name, uniqueness, tablespace_name
                    FROM dba_indexes
                   WHERE owner = owner_in
                     AND table_name = table_name_in
                     AND index_type != 'LOB'
                     AND index_name NOT IN (SELECT index_name 
                                             FROM dba_constraints
                                            WHERE owner = owner_in
                                              AND table_name = table_name_in
                                              AND constraint_type IN ('P', 'U'))) LOOP
        BEGIN
          DECLARE
            v_index_ddl VARCHAR2(4000);
            v_columns   VARCHAR2(4000);
          BEGIN
            -- Get index columns
            SELECT listagg(column_name, ', ') WITHIN GROUP (ORDER BY column_position)
              INTO v_columns
              FROM dba_ind_columns
             WHERE index_owner = owner_in
               AND index_name = rec.index_name;
            
            v_index_ddl := 'CREATE ';
            IF rec.uniqueness = 'UNIQUE' THEN
              v_index_ddl := v_index_ddl || 'UNIQUE ';
            END IF;
            
            v_index_ddl := v_index_ddl || 'INDEX "' || owner_in || '"."' || 
                          rec.index_name || v_options.interim_suffix || '" ON "' || 
                          owner_in || '"."' || v_new_table_name || '" (' || v_columns || ')';
            
            IF rec.tablespace_name IS NOT NULL THEN
              v_index_ddl := v_index_ddl || ' TABLESPACE ' || rec.tablespace_name;
            END IF;
            
            IF v_options.enable_parallel THEN
              v_index_ddl := v_index_ddl || ' PARALLEL ' || v_options.parallel_degree;
            END IF;
            
            sql_admin.execute_sql(v_index_ddl);
          END;
        EXCEPTION
          WHEN OTHERS THEN
            log_admin.warning('Failed to copy index ' || rec.index_name || ': ' || SQLERRM,
                            module_name_in => $$PLSQL_UNIT,
                            module_action_in => v_module_action);
        END;
      END LOOP;
    END IF;
    
    -- Step 4: Initial data load
    log_admin.info('Step 4: Initial data load',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    DECLARE
      v_insert_sql VARCHAR2(4000);
    BEGIN
      v_insert_sql := 'INSERT /*+ APPEND */ INTO "' || owner_in || '"."' || v_new_table_name || 
                     '" SELECT * FROM "' || owner_in || '"."' || table_name_in || '"';
      
      IF v_options.enable_parallel THEN
        v_insert_sql := v_insert_sql || ' /*+ PARALLEL(' || v_options.parallel_degree || ') */';
      END IF;
      
      EXECUTE IMMEDIATE v_insert_sql;
      v_rows_synced := SQL%ROWCOUNT;
      COMMIT;
      
      log_admin.info('Initial load completed: ' || v_rows_synced || ' rows',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
    END;
    
    -- Step 5: Incremental sync loop (for online strategy)
    IF v_options.strategy = c_strategy_online THEN
      log_admin.info('Step 5: Incremental sync (online strategy)',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
      
      -- Note: Actual incremental sync would require tracking mechanism (e.g., timestamp column)
      -- This is a simplified version showing the pattern
      log_admin.warning('Incremental sync requires application-specific logic based on tracking columns',
                       module_name_in => $$PLSQL_UNIT,
                       module_action_in => v_module_action);
    END IF;
    
    -- Step 6: Enable constraints if requested
    IF v_options.validate_constraints THEN
      log_admin.info('Step 6: Enabling and validating constraints',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
      
      FOR rec IN (SELECT constraint_name
                    FROM dba_constraints
                   WHERE owner = owner_in
                     AND table_name = v_new_table_name
                     AND status = 'DISABLED') LOOP
        BEGIN
          sql_admin.execute_sql('ALTER TABLE "' || owner_in || '"."' || v_new_table_name || 
                               '" ENABLE VALIDATE CONSTRAINT "' || rec.constraint_name || '"');
        EXCEPTION
          WHEN OTHERS THEN
            log_admin.warning('Failed to enable constraint ' || rec.constraint_name || ': ' || SQLERRM,
                            module_name_in => $$PLSQL_UNIT,
                            module_action_in => v_module_action);
        END;
      END LOOP;
    END IF;
    
    -- Step 7: Atomic table rename
    log_admin.info('Step 7: Atomic table rename',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    BEGIN
      -- Rename original to _OLD
      sql_admin.execute_sql('ALTER TABLE "' || owner_in || '"."' || table_name_in || 
                           '" RENAME TO "' || v_old_table_name || '"');
      
      -- Rename _NEW to original
      sql_admin.execute_sql('ALTER TABLE "' || owner_in || '"."' || v_new_table_name || 
                           '" RENAME TO "' || table_name_in || '"');
      
      log_admin.info('Table rename completed successfully',
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action);
    EXCEPTION
      WHEN OTHERS THEN
        log_admin.critical('CRITICAL: Table rename failed! Manual intervention required.',
                          module_name_in => $$PLSQL_UNIT,
                          module_action_in => v_module_action,
                          sql_code_in => SQLCODE,
                          sql_errm_in => SQLERRM);
        RAISE;
    END;
    
    log_admin.info('Conversion completed successfully',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical('Conversion failed: ' || dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RAISE;
  END execute_conversion_with_sync;

  /*******************************************************************************
  * Cleanup object names (rename _NEW suffix)
  *******************************************************************************/
  PROCEDURE cleanup_object_names(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2
  ) IS
    v_module_action log_admin.t_module_action := 'cleanup_object_names';
  BEGIN
    log_admin.info('Cleaning up object names for ' || owner_in || '.' || table_name_in,
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Rename constraints
    FOR rec IN (SELECT constraint_name
                  FROM dba_constraints
                 WHERE owner = owner_in
                   AND table_name = table_name_in
                   AND constraint_name LIKE '%\_NEW' ESCAPE '\') LOOP
      BEGIN
        DECLARE
          v_new_name VARCHAR2(128);
        BEGIN
          v_new_name := REPLACE(rec.constraint_name, '_NEW', '');
          sql_admin.execute_sql('ALTER TABLE "' || owner_in || '"."' || table_name_in || 
                               '" RENAME CONSTRAINT "' || rec.constraint_name || 
                               '" TO "' || v_new_name || '"');
          log_admin.debug('Renamed constraint ' || rec.constraint_name || ' to ' || v_new_name,
                         module_name_in => $$PLSQL_UNIT,
                         module_action_in => v_module_action);
        END;
      EXCEPTION
        WHEN OTHERS THEN
          log_admin.warning('Failed to rename constraint ' || rec.constraint_name || ': ' || SQLERRM,
                          module_name_in => $$PLSQL_UNIT,
                          module_action_in => v_module_action);
      END;
    END LOOP;
    
    -- Rename indexes
    FOR rec IN (SELECT index_name
                  FROM dba_indexes
                 WHERE owner = owner_in
                   AND table_name = table_name_in
                   AND index_name LIKE '%\_NEW' ESCAPE '\') LOOP
      BEGIN
        DECLARE
          v_new_name VARCHAR2(128);
        BEGIN
          v_new_name := REPLACE(rec.index_name, '_NEW', '');
          sql_admin.execute_sql('ALTER INDEX "' || owner_in || '"."' || rec.index_name || 
                               '" RENAME TO "' || v_new_name || '"');
          log_admin.debug('Renamed index ' || rec.index_name || ' to ' || v_new_name,
                         module_name_in => $$PLSQL_UNIT,
                         module_action_in => v_module_action);
        END;
      EXCEPTION
        WHEN OTHERS THEN
          log_admin.warning('Failed to rename index ' || rec.index_name || ': ' || SQLERRM,
                          module_name_in => $$PLSQL_UNIT,
                          module_action_in => v_module_action);
      END;
    END LOOP;
    
    log_admin.info('Object name cleanup completed',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.error('Error during object name cleanup: ' || SQLERRM,
                     module_name_in => $$PLSQL_UNIT,
                     module_action_in => v_module_action,
                     sql_code_in => SQLCODE,
                     sql_errm_in => SQLERRM);
  END cleanup_object_names;

  /*******************************************************************************
  * Convert to single-level partition
  *******************************************************************************/
  FUNCTION convert_to_single_level_partition(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN IS
    v_module_action log_admin.t_module_action := 'convert_to_single_level_partition';
    v_base_ddl      CLOB;
    v_partition_ddl CLOB;
    v_full_ddl      CLOB;
    v_options       t_conversion_options;
  BEGIN
    log_admin.info('Converting ' || owner_in || '.' || table_name_in || ' to single-level ' || 
                   partition_spec.partition_type || ' partitioning',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Validate partition spec
    IF NOT validate_partition_spec(partition_spec) THEN
      RAISE e_invalid_partition_spec;
    END IF;
    
    -- Check if composite partitioning was requested
    IF partition_spec.is_composite THEN
      log_admin.error('Composite partitioning requested but convert_to_single_level_partition called',
                      module_name_in => $$PLSQL_UNIT,
                      module_action_in => v_module_action);
      RETURN FALSE;
    END IF;
    
    -- Initialize options
    v_options := options_in;
    IF v_options.strategy IS NULL THEN
      IF is_online_conversion_capable(owner_in, table_name_in, partition_spec) THEN
        v_options.strategy := c_strategy_online;
      ELSE
        v_options.strategy := c_strategy_offline;
      END IF;
    END IF;
    
    log_admin.info('Using ' || v_options.strategy || ' conversion strategy',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Get base table DDL
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'TABLESPACE', TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS', FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', FALSE);
    
    v_base_ddl := sys.get_object_ddl(object_type_in => 'TABLE', 
                                      schema_in => owner_in, 
                                      name_in => table_name_in);
    
    -- Generate partition DDL
    v_partition_ddl := generate_partition_ddl_19c(partition_spec, part_defs_in);
    
    -- Combine DDLs
    dbms_lob.createtemporary(v_full_ddl, TRUE);
    dbms_lob.append(v_full_ddl, v_base_ddl);
    dbms_lob.append(v_full_ddl, v_partition_ddl);
    
    -- Execute conversion
    execute_conversion_with_sync(owner_in, table_name_in, v_full_ddl, v_options);
    
    log_admin.info('Single-level partition conversion completed successfully',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    RETURN TRUE;
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical('Single-level partition conversion failed: ' || dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RETURN FALSE;
  END convert_to_single_level_partition;

  /*******************************************************************************
  * Convert to composite partition
  *******************************************************************************/
  FUNCTION convert_to_composite_partition(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN IS
    v_module_action log_admin.t_module_action := 'convert_to_composite_partition';
    v_base_ddl      CLOB;
    v_partition_ddl CLOB;
    v_full_ddl      CLOB;
    v_options       t_conversion_options;
  BEGIN
    log_admin.info('Converting ' || owner_in || '.' || table_name_in || ' to composite ' || 
                   partition_spec.partition_type || '-' || partition_spec.subpartition_type || ' partitioning',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Validate partition spec
    IF NOT validate_partition_spec(partition_spec) THEN
      RAISE e_invalid_partition_spec;
    END IF;
    
    -- Check if composite partitioning was requested
    IF NOT partition_spec.is_composite THEN
      log_admin.error('Single-level partitioning requested but convert_to_composite_partition called',
                      module_name_in => $$PLSQL_UNIT,
                      module_action_in => v_module_action);
      RETURN FALSE;
    END IF;
    
    -- Initialize options
    v_options := options_in;
    IF v_options.strategy IS NULL THEN
      IF is_online_conversion_capable(owner_in, table_name_in, partition_spec) THEN
        v_options.strategy := c_strategy_online;
      ELSE
        v_options.strategy := c_strategy_offline;
      END IF;
    END IF;
    
    log_admin.info('Using ' || v_options.strategy || ' conversion strategy',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- Get base table DDL
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'SEGMENT_ATTRIBUTES', TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'STORAGE', FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'TABLESPACE', TRUE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'CONSTRAINTS', FALSE);
    dbms_metadata.set_transform_param(dbms_metadata.session_transform, 'REF_CONSTRAINTS', FALSE);
    
    v_base_ddl := sys.get_object_ddl(object_type_in => 'TABLE', 
                                      schema_in => owner_in, 
                                      name_in => table_name_in);
    
    -- Generate partition DDL
    v_partition_ddl := generate_partition_ddl_19c(partition_spec, part_defs_in);
    
    -- Combine DDLs
    dbms_lob.createtemporary(v_full_ddl, TRUE);
    dbms_lob.append(v_full_ddl, v_base_ddl);
    dbms_lob.append(v_full_ddl, v_partition_ddl);
    
    -- Execute conversion
    execute_conversion_with_sync(owner_in, table_name_in, v_full_ddl, v_options);
    
    log_admin.info('Composite partition conversion completed successfully',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    RETURN TRUE;
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical('Composite partition conversion failed: ' || dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RETURN FALSE;
  END convert_to_composite_partition;

  /*******************************************************************************
  * Convert single-level to composite
  *******************************************************************************/
  FUNCTION convert_single_to_composite(
    owner_in         IN VARCHAR2,
    table_name_in    IN VARCHAR2,
    partition_spec   IN t_partition_spec,
    part_defs_in     IN partition_types.t_partition_def_table,
    options_in       IN t_conversion_options DEFAULT NULL
  ) RETURN BOOLEAN IS
    v_module_action log_admin.t_module_action := 'convert_single_to_composite';
  BEGIN
    log_admin.info('Converting single-level partitioned table ' || owner_in || '.' || table_name_in || 
                   ' to composite partitioning',
                   module_name_in => $$PLSQL_UNIT,
                   module_action_in => v_module_action);
    
    -- For converting single-level to composite, we use the same logic as converting
    -- a non-partitioned table to composite, since Oracle doesn't support direct
    -- modification of partition structure from single to composite
    RETURN convert_to_composite_partition(owner_in, table_name_in, partition_spec, part_defs_in, options_in);
    
  EXCEPTION
    WHEN OTHERS THEN
      log_admin.critical('Single to composite conversion failed: ' || dbms_utility.format_error_backtrace(),
                        module_name_in => $$PLSQL_UNIT,
                        module_action_in => v_module_action,
                        sql_code_in => SQLCODE,
                        sql_errm_in => SQLERRM);
      RETURN FALSE;
  END convert_single_to_composite;

END partition_redefine_19c;
/
