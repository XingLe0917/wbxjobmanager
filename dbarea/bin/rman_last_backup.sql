set lines 151 pages 100
col status for a23
select * from ( 
select a.db_name "Database", 
       db.dbid "DBID", db.RESETLOGS_TIME, 
       to_char(a.end_time,'YYYY-MM-DD HH24:MI:SS') "Latest Backup", 
       a.output_bytes/1024/1024/1024 "GB Processed", 
       (end_time - start_time) * 60 * 60 * 24 "Seconds Taken", 
       status, round(sysdate - a.end_time) "Days Behind" 
from RACAXMMP.rc_rman_status a, (select * from RACAXMMP.rc_database where RESETLOGS_TIME = (select max(RESETLOGS_TIME) from RACAXMMP.rc_database))  db 
where object_type in ('DB FULL') 
       and operation = 'BACKUP' 
       and db.db_key = a.db_key 
       and end_time = (select max(end_time) from RACAXMMP.rc_rman_status b 
                        where b.db_key = db.db_key 
                        and b.db_name = a.db_name 
                        and object_type in ('DB FULL') 
                        and operation = 'BACKUP' 
                       ) 
union all 
select a.db_name "Database", 
       db.dbid "DBID", db.RESETLOGS_TIME, 
       to_char(a.end_time,'YYYY-MM-DD HH24:MI:SS') "Latest Backup", 
       a.output_bytes/1024/1024/1024 "GB Processed", 
       (end_time - start_time) * 60 * 60 * 24 "Seconds Taken", 
       status, round(sysdate - a.end_time) "Days Behind" 
from RACAXWEB.rc_rman_status a, (select * from RACAXWEB.rc_database where RESETLOGS_TIME = (select max(RESETLOGS_TIME) from RACAXWEB.rc_database))  db 
where object_type in ('DB FULL') 
       and operation = 'BACKUP' 
       and db.db_key = a.db_key 
       and end_time = (select max(end_time) from RACAXWEB.rc_rman_status b 
                        where b.db_key = db.db_key 
                        and b.db_name = a.db_name 
                        and object_type in ('DB FULL') 
                        and operation = 'BACKUP' 
                       ) 
union all 
select a.db_name "Database", 
       db.dbid "DBID", db.RESETLOGS_TIME, 
       to_char(a.end_time,'YYYY-MM-DD HH24:MI:SS') "Latest Backup", 
       a.output_bytes/1024/1024/1024 "GB Processed", 
       (end_time - start_time) * 60 * 60 * 24 "Seconds Taken", 
       status, round(sysdate - a.end_time) "Days Behind" 
from RACJWEB.rc_rman_status a, (select * from RACJWEB.rc_database where RESETLOGS_TIME = (select max(RESETLOGS_TIME) from RACJWEB.rc_database))  db 
where object_type in ('DB FULL') 
       and operation = 'BACKUP' 
       and db.db_key = a.db_key 
       and end_time = (select max(end_time) from RACJWEB.rc_rman_status b 
                        where b.db_key = db.db_key 
                        and b.db_name = a.db_name 
                        and object_type in ('DB FULL') 
                        and operation = 'BACKUP' 
                       ) 
) 
order by 7 desc, 8 desc;
