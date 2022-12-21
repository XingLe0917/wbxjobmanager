spool /u00/app/admin/dbarea/log/asm_storage_fra
set echo off
set verify off
column "% LEFT_PER" format 99.99;
select name,TOTAL_MB,FREE_MB, FREE_MB*100/TOTAL_MB "% LEFT_PER" from v$asm_diskgroup where FREE_MB/TOTAL_MB <0.1 and name like '%FRA%';
--select name,TOTAL_MB,FREE_MB, FREE_MB*100/TOTAL_MB "% LEFT_PER" from v$asm_diskgroup where name like '%FRA%';
spool off

