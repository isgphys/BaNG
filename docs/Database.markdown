BaNG Database
=============


Basics
------

BaNG uses a **MySQL** database to store backup statistics. It can be hosted on any server and should be configured through `etc/bangstat_db.yaml`.


Initial Setup
-------------

### Create database

```sql
CREATE DATABASE bangstat;
USE bangstat;
```

### Create user

```sql
GRANT USAGE
    ON *.*
    TO 'bang'@'localhost'
    IDENTIFIED BY 'secret-password';

GRANT
    SELECT, INSERT, UPDATE, DELETE, LOCK TABLES
    ON `bangstat`.*
    TO 'bang'@'localhost';

FLUSH PRIVILEGES;
```

### Create tables

```sql
CREATE TABLE statistic (
    ID int(11) NOT NULL AUTO_INCREMENT,
    TaskID varchar(24) DEFAULT NULL,
    JobID varchar(24) DEFAULT NULL,
    TimeStamp timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Start DATETIME NULL DEFAULT NULL,
    Stop DATETIME NULL DEFAULT NULL,
    BkpFromHost varchar(30) NOT NULL,
    BkpGroup varchar(30) DEFAULT NULL,
    BkpFromPath varchar(250) DEFAULT NULL,
    BkpFromPathRoot varchar(250) DEFAULT NULL,
    BkpToHost varchar(30) DEFAULT NULL,
    BkpToPath varchar(250) DEFAULT NULL,
    isThread tinyint(1) DEFAULT NULL,
    ErrStatus bigint(20) DEFAULT '0',
    JobStatus tinyint(1) DEFAULT '0',
    NumOfFiles bigint(20) DEFAULT NULL,
    NumOfFilesTrans bigint(20) DEFAULT NULL,
    NumOfFilesCreated bigint(20) DEFAULT NULL,
    NumOfFilesDel bigint(20) DEFAULT NULL,
    TotFileSize bigint(20) DEFAULT NULL COMMENT 'in bytes',
    TotFileSizeTrans bigint(20) DEFAULT NULL,
    LitData bigint(20) DEFAULT NULL COMMENT 'in bytes',
    MatchData bigint(20) DEFAULT NULL COMMENT 'in bytes',
    FileListSize bigint(20) DEFAULT NULL COMMENT 'in bytes',
    FileListGenTime decimal(10,3) DEFAULT NULL COMMENT 'in sec',
    FileListTransTime decimal(10,3) DEFAULT NULL COMMENT 'in sec',
    TotBytesSent bigint(20) DEFAULT NULL COMMENT 'in bytes',
    TotBytesRcv bigint(20) DEFAULT NULL COMMENT 'in bytes',
    BytesPerSec decimal(10,3) DEFAULT NULL COMMENT 'in bytes',
    Speedup decimal(10,3) DEFAULT NULL,
    PRIMARY KEY (ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;

CREATE TABLE statistic_archive LIKE statistic;

CREATE TABLE statistic_task_meta (
    ID int(11) NOT NULL AUTO_INCREMENT,
    TaskID varchar(24) DEFAULT NULL,
    TaskName varchar(120) DEFAULT NULL,
    Description varchar(250) DEFAULT NULL,
    Cron tinyint(1) DEFAULT '0',
    PRIMARY KEY (ID)
) ENGINE=InnoDB DEFAULT CHARSET=utf8;
```

### Create indexes

```sql
CREATE INDEX TaskID ON statistic (TaskID);
CREATE INDEX JobID ON statistic (JobID);
CREATE INDEX BkpFromHost ON statistic (BkpFromHost);
CREATE INDEX BkpFromPath ON statistic (BkpFromPath);
CREATE INDEX BkpToHost ON statistic (BkpToHost);
CREATE INDEX Start ON statistic (Start);
```

Misc commands
-------------

View columns of table `statistics` in database `bangstat`

```sql
use bangstat;
describe statistic;
```

Use profiling to view query statistics

```sql
set profiling = 1;
show profiles;
show profile for query 1;
```

Change MySQL engine from `MyISAM` to `InnoDB`

```sql
ALTER TABLE statistic ENGINE = InnoDB;
```
