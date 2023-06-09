CREATE OR ALTER PROCEDURE [dbo].[stp_ImportCsvFile] 
    @FileName varchar(max),
	@ResultTableName varchar(50) = null, --if not passed, create a temp table, select, delete; if passed, assume table exists with LineNumber columns
	@DataSource varchar(50) = null -- filled for cloud
AS

BEGIN
    DECLARE @Debug bit = 'false'
    DECLARE @sql as varchar(max)
	DECLARE @deleteTempTable bit = 0

    SET NOCOUNT ON
		 
		IF @ResultTableName IS NULL
		BEGIN
			set @deleteTempTable = 1
			IF OBJECT_ID('tempdb..#BulkWithID') IS NOT NULL DROP TABLE #BulkWithID
			CREATE TABLE #BulkWithID (LineNumber int)
			set @ResultTableName = '#BulkWithID'
		END
		--ELSE assume table exists and has a column called LineNumber

		IF OBJECT_ID('tempdb..#FileColumnNames') IS NOT NULL DROP TABLE #FileColumnNames
		CREATE TABLE #FileColumnNames ([ColumnNumber] int, [ColumnName] NVARCHAR(max) )

		IF @DataSource IS NULL 
			SET @DataSource = (SELECT top 1 name from sys.external_data_sources where type_desc = 'blob_storage')
		SELECT @DataSource = ISNULL( 'DATA_SOURCE = ''' + @DataSource + ''', ', '')

	    --1. create a table to hold the column headers from the file
        IF @Debug = 1 print 'step 1a'
        BEGIN
	        IF OBJECT_ID('tempdb..#FileColumns') IS NOT NULL DROP TABLE #FileColumns
            CREATE TABLE #FileColumns(columnNames varchar(max));

            --DECLARE @sql as varchar(max)
            SELECT @sql = 'bulk insert #FileColumns from ''' + @FileName + '''
            with (' + @DataSource + 'FirstRow = 1, LastRow = 1, RowTerminator = ''\n'')'
            exec(@sql)

		    update #FileColumns set columnNames = REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(columnNames)), CHAR(10), ''), CHAR(13), ''), CHAR(9), '')

		    INSERT INTO #FileColumnNames
            select ItemNumber as ColumnNumber, ItemValue as ColumnName from #FileColumns 
            cross apply [fn_CsvToTable](columnNames) 
	    END

	    --2. load the data, single column with csv value
        IF @Debug = 1 print 'step 1b'
	    BEGIN
		    IF OBJECT_ID('tempdb..#BulkTemp') IS NOT NULL DROP TABLE #BulkTemp
            CREATE TABLE #BulkTemp (WholeRow nvarchar(max))

            select @sql = 'bulk insert #BulkTemp from ''' + @FileName + '''
                with (' + @DataSource + 'FirstRow = 2, RowTerminator = ''\n'');'
            exec(@sql)
        END

	    --3. alter table to hold individual fields and extra fields
        IF @Debug = 1 print 'step 1c'
        BEGIN

            SELECT @sql = 'ALTER table ' + @ResultTableName + ' Add [' + replace(columnNames,',','] nvarchar(MAX); 
                ALTER table ' + @ResultTableName + ' Add [') + '] nvarchar(MAX);'
            FROM #FileColumns
            EXEC(@sql)
        END

	    --4. parse each row into individual fields, set defaults for extra fields
        IF @Debug = 1 print 'step 1d'
        BEGIN
		    declare @selectString nvarchar(max) = (SELECT STUFF((
					    select ',['+ cast(ColumnNumber  as varchar(5)) + '] [' + ColumnName +']' from #FileColumnNames FOR XML PATH('') ),1,1,'')) 
		    declare @pivotString nvarchar(max) = (SELECT STUFF((
					    select ',['+ cast(ColumnNumber  as varchar(5)) + ']' from #FileColumnNames FOR XML PATH('') ),1,1,''))
		
		    set @sql = N'
		    INSERT INTO ' + @ResultTableName + '
		    select LineNumber + 1, ' + @selectString +' from (
				    select LineNumber, ItemNumber, ItemValue from (
				    select ROW_NUMBER() OVER(ORDER BY (SELECT NULL)) as LineNumber, wholeRow from #BulkTemp ) as a
				    CROSS APPLY [fn_CSVToTable](wholeRow) as test
		    ) src
		    pivot
		    ( MAX(ItemValue) for ItemNumber in (' + @pivotString +') ) p
		    '
		    --print (@sql)
		    exec (@sql)
        END

		if @deleteTempTable = 1
		    exec ('select * from ' + @ResultTableName + '; DROP TABLE ' + @ResultTableName )

	    DROP TABLE #FileColumns
	    DROP TABLE #BulkTemp
    END