set line 50
set head off
set echo off
set verify off
set feedback off
set pages 0
select'alter system kill session '''||gv$session.sid||','||SERIAL#||''' immediate;' from gv$session 
where machine like 'sjdbop1%'
and USERNAME ='TEST'
and status like 'AC%';
