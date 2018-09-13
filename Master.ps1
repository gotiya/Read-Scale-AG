Set-Location -Path "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql1"
& ".\Start.ps1"
Set-Location -Path "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql2"
& ".\Start.ps1"
Write-Host "Enabling AlwaysOn mysql10"
docker exec -it mysql10 powershell Enable-SQLAlwaysOn -InputObject mysql10 -Force -NoServiceRestart
Write-Host "Stopping mysql10"
docker stop mysql10
Write-Host "Enabling AlwaysOn mysql11"
docker exec -it mysql11 powershell Enable-SQLAlwaysOn -InputObject mysql11 -Force -NoServiceRestart
Write-Host "Stopping mysql11"
docker stop mysql11
Write-Host "Starting all container services"
docker start mysql10 mysql11
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; EXEC sp_configure 'show advanced options', 1; RECONFIGURE; exec sp_configure N'Agent XPs' , 1; RECONFIGURE WITH OVERRIDE; exec xp_servicecontrol N'Start', N'SqlServerAGENT';"
docker exec -it mysql11 sqlcmd -Q "SET NOCOUNT ON; EXEC sp_configure 'show advanced options', 1; RECONFIGURE; exec sp_configure N'Agent XPs' , 1; RECONFIGURE WITH OVERRIDE; exec xp_servicecontrol N'Start', N'SqlServerAGENT';"
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; create master key encryption by password=N'myP@$$word'; create certificate [mysql10_cert] with subject=N'mysql10_cert'; create login [mysql11_login] with password = 'myP@$$w0rd'; create user [mysql11_user] for login [mysql11_login]; backup certificate [mysql10_cert] to file=N'C:\sqldata\mysql10_cert.cer';"
docker exec -it mysql11 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; create master key encryption by password=N'myP@$$word'; create certificate [mysql11_cert] with subject=N'mysql11_cert'; create login [mysql10_login] with password=N'myP@$$w0rd'; create user [mysql10_user] for login [mysql10_login]
; backup certificate [mysql11_cert] to file=N'C:\sqldata\mysql11_cert.cer';"
docker stop mysql10 mysql11
Copy-Item "C:\Users\Abhay Kanare\mssql-docker\windows\examples\Read-Scale-AG\msql1\cvols\mysql10_cert.cer" -Destination "C:\Users\Abhay Kanare\mssql-docker\windows\examples\Read-Scale-AG\msql2\cvols\mysql10_cert.cer"
Copy-Item "C:\Users\Abhay Kanare\mssql-docker\windows\examples\Read-Scale-AG\msql2\cvols\mysql11_cert.cer" -Destination "C:\Users\Abhay Kanare\mssql-docker\windows\examples\Read-Scale-AG\msql1\cvols\mysql11_cert.cer"
docker start mysql10 mysql11
Start-Sleep -s 10
Write-Host "Creating the certificates"
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; create certificate [mysql11_cert] authorization [mysql11_user] from file=N'C:\\sqldata\\mysql11_cert.cer';"
docker exec -it mysql11 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; create certificate [mysql10_cert] authorization [mysql10_user] from file=N'C:\\sqldata\\mysql10_cert.cer';"

Start-Sleep -s 10
Write-Host "Creating the endpoints"
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; CREATE ENDPOINT WGAG_Endpoint STATE=STARTED AS TCP (LISTENER_PORT=5022, LISTENER_IP=ALL) FOR DATABASE_MIRRORING (AUTHENTICATION=CERTIFICATE [mysql10_cert], ROLE=ALL); GRANT CONNECT ON ENDPOINT::WGAG_Endpoint TO [mysql11_login]; IF (SELECT state FROM sys.endpoints WHERE name = N'WGAG_Endpoint') <> 0 BEGIN ALTER ENDPOINT [WGAG_Endpoint] STATE=STARTED; END; IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='AlwaysOn_health') BEGIN ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON); END; IF NOT EXISTS(SELECT * FROM sys.dm_xe_sessions WHERE name='AlwaysOn_health') BEGIN ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START; END;"
docker exec -it mysql11 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; CREATE ENDPOINT WGAG_Endpoint STATE=STARTED AS TCP (LISTENER_PORT=5022, LISTENER_IP=ALL) FOR DATABASE_MIRRORING (AUTHENTICATION=CERTIFICATE [mysql11_cert], ROLE=ALL); GRANT CONNECT ON ENDPOINT::WGAG_Endpoint TO [mysql10_login]; IF (SELECT state FROM sys.endpoints WHERE name=N'WGAG_Endpoint') <> 0  BEGIN ALTER ENDPOINT [WGAG_Endpoint] STATE = STARTED; END; IF EXISTS(SELECT * FROM sys.server_event_sessions WHERE name='AlwaysOn_health') BEGIN ALTER EVENT SESSION [AlwaysOn_health] ON SERVER WITH (STARTUP_STATE=ON); END; IF NOT EXISTS(SELECT * FROM sys.dm_xe_sessions WHERE name='AlwaysOn_health') BEGIN ALTER EVENT SESSION [AlwaysOn_health] ON SERVER STATE=START; END;"

Start-Sleep -s 10

Write-Host "Backup the test database & tlog on Primary server"
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; use master; backup database [test] to disk = N'C:\sqldata\test.bak'; backup log [test] to disk = N'C:\sqldata\test.trn'"

Start-Sleep -s 10
Write-Host "Creating the AG on Primary"
docker exec -it mysql10 sqlcmd -Q "SET NOCOUNT ON; USE MASTER; CREATE AVAILABILITY GROUP [MyAG] WITH (CLUSTER_TYPE = NONE) FOR DATABASE [test] REPLICA ON N'mysql11' WITH (ENDPOINT_URL = N'TCP://mysql11:5022', FAILOVER_MODE = MANUAL, AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO)), N'mysql10' WITH (ENDPOINT_URL = N'TCP://mysql10:5022', FAILOVER_MODE = MANUAL, AVAILABILITY_MODE = ASYNCHRONOUS_COMMIT, BACKUP_PRIORITY = 50, SECONDARY_ROLE(ALLOW_CONNECTIONS = NO));"

Start-Sleep -s 10
docker stop mysql10 mysql11
Copy-Item "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql1\cvols\test.bak" -Destination "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql2\cvols\test.bak"
Copy-Item "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql1\cvols\test.trn" -Destination "C:\gitrepo\mssql-docker\windows\examples\Read-Scale-AG\msql2\cvols\test.trn"
docker start mysql10 mysql11
Start-Sleep -s 10
Write-Host "Restoring the databases on Secondary and creating AG"
docker exec -it mysql11 sqlcmd -Q "use master; restore database [test] from disk = N'C:\sqldata\test.bak' with move N'test_data' to N'C:\sqldata\test_data.mdf', move N'test_log' to N'C:\sqldata\test_log.ldf',NOUNLOAD, norecovery,replace; ALTER AVAILABILITY GROUP [MyAG] JOIN WITH (CLUSTER_TYPE = NONE);ALTER AVAILABILITY GROUP [MYAG] GRANT CREATE ANY DATABASE"

Set-Location -Path "C:\Users\Abhay Kanare\mssql-docker\windows\examples\Read-Scale-AG"