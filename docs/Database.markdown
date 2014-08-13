BaNG Database
=============

Basics
------

BaNG uses a **MySQL** database to store backup statistics.

View columns of table ```statistics``` in database ```bangstat```

    use bangstat;
    describe statistic;

Use profiling to view query statistics

    set profiling = 1;
    show profiles;
    show profile for query 1;

Change MySQL engine from ```MyISAM``` to ```InnoDB```

    ALTER TABLE mytable ENGINE = InnoDB;

Create database and user
------------------------

    CREATE DATABASE bangstat;
    USE bangstat;

    GRANT USAGE
        ON *.*
        TO 'bang'@'localhost'
        IDENTIFIED BY 'secret-password';

    GRANT
        SELECT,INSERT,UPDATE,DELETE
        ON `bangstat`.*
        TO 'bang'@'localhost';

    FLUSH PRIVILEGES;

Create table
------------

    CREATE TABLE statistic (
      ID int(11) NOT NULL AUTO_INCREMENT,
      TaskID varchar(24) DEFAULT NULL,
      JobID varchar(24) DEFAULT NULL,
      TimeStamp timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
      Start timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
      Stop timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
      BkpFromHost varchar(30) NOT NULL,
      BkpGroup varchar(30) DEFAULT NULL,
      BkpFromPath varchar(250) DEFAULT NULL,
      BkpToHost varchar(30) NOT NULL,
      BkpToPath varchar(250) DEFAULT NULL,
      LastBkp varchar(30) DEFAULT NULL,
      isThread tinyint(1) DEFAULT NULL,
      ErrStatus bigint(20) DEFAULT '0',
      JobStatus tinyint(1) DEFAULT '0',
      NumOfFiles bigint(20) NOT NULL,
      NumOfFilesTrans bigint(20) NOT NULL,
      NumOfFilesCreated bigint(20) NOT NULL,
      NumOfFilesDel bigint(20) NOT NULL,
      TotFileSize bigint(20) NOT NULL COMMENT 'in bytes',
      TotFileSizeTrans bigint(20) NOT NULL,
      LitData bigint(20) NOT NULL COMMENT 'in bytes',
      MatchData bigint(20) NOT NULL COMMENT 'in bytes',
      FileListSize bigint(20) NOT NULL COMMENT 'in bytes',
      FileListGenTime decimal(10,3) NOT NULL COMMENT 'in sec',
      FileListTransTime decimal(10,3) NOT NULL COMMENT 'in sec',
      TotBytesSent bigint(20) NOT NULL COMMENT 'in bytes',
      TotBytesRcv bigint(20) NOT NULL COMMENT 'in bytes',
      BytesPerSec decimal(10,3) DEFAULT NULL COMMENT 'in bytes',
      Speedup decimal(10,3) DEFAULT NULL,
      PRIMARY KEY (ID)
    ) ENGINE=InnoDB AUTO_INCREMENT=194120 DEFAULT CHARSET=utf8;

Create views
------------

    CREATE OR REPLACE VIEW recent_backups AS
    SELECT TaskID, JobID, MIN(Start) as Start, MAX(Stop) as Stop, TIMESTAMPDIFF(Second, MIN(Start) , MAX(Stop)) as Runtime, BkpFromHost,
    IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),BkpFromPath) as BkpFromPath,
    BkpToHost, BkpToPath, LastBkp, isThread, BkpGroup, SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
        SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSizeTrans) as TotFileSizeTrans,
    GROUP_CONCAT(DISTINCT ErrStatus order by ErrStatus) as ErrStatus, JobStatus
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    GROUP BY JobID;

    CREATE OR REPLACE VIEW statistic_job_sum AS
    SELECT TaskID, JobID, MIN(Start) as Start, MAX(Stop) as Stop, TIMESTAMPDIFF(Second, MIN(Start) , Max(Stop)) as Runtime,
    BkpFromHost, IF(isThread,SUBSTRING_INDEX(BkpFromPath,'/',(LENGTH(BkpFromPath)-LENGTH(REPLACE(BkpFromPath,'/','')))),
    BkpFromPath) as BkpFromPath, BkpToHost, BkpToPath, LastBkp, isThread = Null as isThread, JobStatus, BkpGroup,
    SUM(NumOfFilesCreated) as NumOfFilesCreated, SUM(NumOfFilesDel) as NumOfFilesDel,
    SUM(NumOfFiles) as NumOfFiles, SUM(NumOfFilesTrans) as NumOfFilesTrans, SUM(TotFileSize) as TotFileSize,
    SUM(TotFileSizeTrans) as TotFileSizeTrans
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    GROUP BY JobID;

    CREATE OR REPLACE VIEW statistic_job_thread AS
    SELECT TaskID, JobID, Start, Stop, TIMESTAMPDIFF(Second, Start, Stop) as Runtime,
    BkpFromHost, BkpFromPath, BkpToHost, BkpToPath, LastBkp, isThread, JobStatus, BkpGroup,
    NumOfFilesCreated, NumOfFilesDel, NumOfFiles, NumOfFilesTrans, TotFileSize, TotFileSizeTrans
    FROM statistic
    WHERE Start > date_sub(NOW(), INTERVAL 100 DAY)
    AND isThread = 1;

    CREATE OR REPLACE VIEW statistic_all AS
    SELECT * FROM statistic_job_sum
    UNION
    SELECT * FROM statistic_job_thread;
