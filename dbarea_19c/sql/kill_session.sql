spool /u00/app/admin/dbarea/log/kill_inactive_sessions.log

alter system kill session '385, 24561';
!kill -9 89092

spool off
