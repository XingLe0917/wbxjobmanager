set lines 150
select a.db_name "Database",
       db.dbid "DBID", db.RESETLOGS_TIME,
       to_char(a.end_time,'HH24:MI:SS MM/DD/YYYY') "Latest Backup",
       a.output_bytes/1024/1024/1024 "GB Processed",
       (end_time - start_time) * 60 * 60 * 24 "Seconds Taken",
       status
       from rc_rman_status a, (select * from rc_database where RESETLOGS_TIME = (select max(RESETLOGS_TIME) from rc_database))  db
where object_type in ('DB FULL')
       and status LIKE  'COMPLETED%'
       and operation = 'BACKUP'
--       and trunc(end_time)<trunc(sysdate)-2
       and db.db_key = a.db_key
       and end_time = (select max(end_time) from rc_rman_status b
                        where b.db_key = db.db_key
                        and b.db_name = a.db_name
                        and object_type in ('DB FULL')
                        and status LIKE  'COMPLETED%'
                        and operation = 'BACKUP'
                       )
order by end_time;

