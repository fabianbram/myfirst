USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_TMP_RAB_MESSAGES_ENTVOU]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO






CREATE PROCEDURE [dbo].[REFRESH_TMP_RAB_MESSAGES_ENTVOU]
AS

DECLARE @CUT_OFF_DATE NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(150);
DECLARE @QUERY_RABO NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @INC_COL NVARCHAR(100);
DECLARE @REP_ALL bit;
DECLARE @TABLE_TO_CREATE NVARCHAR(150);
DECLARE @TABLE_TO_CREATE_SCHEMA NVARCHAR(150);
DECLARE @COUNTER INT;
DECLARE @BATCH_COUNTER INT;
DECLARE @ROWCOUNT INT;

-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE
		, INCREMENTAl_COL
		, REPROCESS_ALL
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1  
	ORDER BY [ORDER] ASC;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'TMP_RAB_MESSAGES_ENTVOU';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE,@INC_COL,@REP_ALL
		
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		DECLARE @MAX_DATE NVARCHAR(50);
		DECLARE @INSERT NVARCHAR(50);
		DECLARE @INSERT_INTO NVARCHAR(50);
		DECLARE @THRESHOLD NVARCHAR(100);

		SET @PRINT_MSG = 'PROCESSING COUNTRY: ' + @COUNTRY_CODE
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT

		SET @ROWCOUNT = 26		
		WHILE(@ROWCOUNT > 25)
		BEGIN
				

		IF (EXISTS (SELECT 1 FROM INFORMATION_SCHEMA.TABLES 
			WHERE TABLE_CATALOG = @TABLE_TO_CREATE_SCHEMA AND TABLE_NAME = @TABLE_TO_CREATE))
		BEGIN
			IF (@REP_ALL = 1) 
			BEGIN
			  DECLARE @DROP_QUERY NVARCHAR(250) = 'DROP TABLE ' + @TABLE_TO_CREATE; 		
			  EXEC(@DROP_QUERY);
	        END	

			DECLARE @IN_SQL NVARCHAR(MAX);			
			SET @INSERT = 'INSERT INTO ' +  @TABLE_TO_CREATE;
			SET @INSERT_INTO='';	
			SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(convert(nvarchar,' + @INC_COL + ',121)),''1900-01-01 00:00:00'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
			SET @THRESHOLD = N'@EXTRACT_THRESHOLD NVARCHAR(100) OUTPUT';			
			-- get date for current country
			EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
		END
		ELSE
		BEGIN	
			SET @THRESHOLD = '1900-01-01 00:00:00';	
			SET @INSERT = '';
			SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
		END
				
		SET @BATCH_COUNTER = 1000000;	  
		-- QUERY HERE
		SET @QUERY_RABO =(@INSERT +  char(13) + char(10)) + 
		   ' SELECT  
		    ID_COMPANY,
			created_at as COD_TIMESTAMP,
			message_id, 
			reverse(substring(reverse(substring(body,0,CHARINDEX(''","Refund'',body))),0,CHARINDEX(''"'',reverse(substring(body,0,CHARINDEX(''","Refund'',body)))))) AS fk_erp_navision_entity	,
			status,
			error,
			type,	
		
			Message_Rank		  
			' + @INSERT_INTO + '			  
				FROM(SELECT * FROM OPENQUERY([BI-DWH-JUMIA], ''
							  SELECT * from (SELECT ''''' + @COUNTRY_CODE +  ''''' AS ID_COMPANY
									, created_at
									, message_id
									, body
									, status 
									, error 
									,type 
																	
									,ROW_NUMBER() OVER(PARTITION BY fk_erp_navision_entity, ''''' + @COUNTRY_CODE +  '''''  ORDER BY created_at  DESC) as Message_Rank
						FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].PRE_NAV_BOB_RABBIT_MQ_REQUEST_ENTVOU
						WHERE created_at  > ''''' + @THRESHOLD + ''''') aux WHERE Message_Rank=1 '')) nav_data';		

		
		EXEC(@QUERY_RABO)
		SET @ROWCOUNT = @@ROWCOUNT
	    
		-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
  END

		FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;

WITH CTE AS 
(SELECT fk_erp_navision_entity	
		,ID_COMPANY
		, COD_TIMESTAMP
		, Message_Rank
		, rn = row_number() over(
				partition by id_company,fk_erp_navision_entity	
				order by [COD_TIMESTAMP] desc)
  FROM TMP_RAB_MESSAGES_ENTVOU
)
DELETE FROM CTE WHERE rn > 1












GO
