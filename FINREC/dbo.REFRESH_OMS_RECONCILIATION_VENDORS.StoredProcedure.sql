USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_VENDORS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_VENDORS]
AS
-- drop table OMS_RECONCILIATION_VENDORS
DECLARE @CUT_OFF_DATE NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_NAV NVARCHAR(MAX);
DECLARE @QUERY_RABBIT NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @INC_COL NVARCHAR(50);
DECLARE @REP_ALL bit;
DECLARE @TABLE_TO_CREATE NVARCHAR(150);
DECLARE @TABLE_TO_CREATE_SCHEMA NVARCHAR(150);
DECLARE @COUNTER INT;
DECLARE @BATCH_COUNTER INT;
DECLARE @ROWCOUNT INT;

SET @PRINT_MSG = 'OMS_RECONCILIATION_VENDORS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT1];

SET @PRINT_MSG = '==== PROCESSING NAVISION MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];

-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE
		, INCREMENTAl_COL
		, REPROCESS_ALL
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1 ORDER BY [Order] asc;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_VENDORS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE,@INC_COL,@REP_ALL
		
	SET @COUNTER = 1;
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		DECLARE @MAX_DATE NVARCHAR(50);
		DECLARE @INSERT NVARCHAR(50);
		DECLARE @INSERT_INTO NVARCHAR(50);
		DECLARE @THRESHOLD NVARCHAR(100);

		SET @PRINT_MSG = 'PROCESSING COUNTRY: ' + @COUNTRY_CODE
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
				
		SELECT 1
		SET @ROWCOUNT = @@ROWCOUNT		
		WHILE(@ROWCOUNT != 0)
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
				  SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(' + @INC_COL + '),''19000101000000'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
				  SET @THRESHOLD = N'@EXTRACT_THRESHOLD varchar(100) OUTPUT';			
				  -- get date for current country
				  EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
			  END
			  ELSE
			  BEGIN	
				  SET @THRESHOLD = '19000101000000';	
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END
			SET @BATCH_COUNTER = 100000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT  
				  OMS_DATA.ID_COMPANY AS ID_Company
				  ,OMS_DATA.COD_BOB_SUPPLIER AS OMS_Vendor_No 
				  ,OMS_DATA.DSC_SUPPLIER_NAME as OMS_Vendor_Name
				  ,(CASE WHEN OMS_DATA.DSC_SUPPLIER_TYPE=''merchant'' then ''Marketplace'' ELSE ''Retail'' END) AS OMS_Vendor_Type
				  ,LEFT(OMS_DATA.COD_TIMESTAMP,4)+''-''+RIGHT(LEFT(OMS_DATA.COD_TIMESTAMP,6),2)+''-''+RIGHT(LEFT(OMS_DATA.COD_TIMESTAMP,8),2) AS OMS_Creation_Date
				  ,(CASE WHEN RABO_DATA.[COD_TIMESTAMP] is null then ''False'' ELSE ''True'' END) AS OMS_Message_Created 
				  ,RABO_DATA.[id_message] AS OMS_Message_ID
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,(CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END)  AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] as Nav_Message_Status
				  ,NAV_DATA.[Error Message] as Nav_Error_Message
				  ,CASE WHEN NAV_DATA_OP.[V_NO] IS NULL THEN ''False'' ELSE ''True'' END as Nav_Vendor_Created 	
				  ,OMS_DATA.COD_TIMESTAMP
				  ,LEFT(OMS_DATA.COD_TIMESTAMP,4) AS OMS_Creation_Year
				  ' + @INSERT_INTO + '
			      FROM( SELECT * FROM OPENQUERY([BI-DWH-JUMIA], ''select * from(SELECT DS_INT.*
																   , row_number() over(order by DS_INT.COD_TIMESTAMP ASC) as rn
															from (SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
															 ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
															 ,PS.COD_BOB_SUPPLIER
															 ,PS.DSC_SUPPLIER_NAME
															 ,PS.DSC_SUPPLIER_TYPE
															 ,PS.COD_TIMESTAMP
														  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SUPPLIER] AS PS
													  	  WHERE PS.COD_TIMESTAMP > ' + @THRESHOLD + ' ) DS_INT ) aux
															where aux.rn <= ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '											 
															'')) AS OMS_DATA' );

SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENT1] AS RABO_DATA 
				   ON CAST(RABO_DATA.id_related_entity AS NVARCHAR) = CAST(OMS_DATA.[COD_BOB_SUPPLIER] AS NVARCHAR) 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT ID_COMPANY,
												 V.[No_] as V_NO 								  
					    FROM [dbo].[Vendors] AS V						
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON CAST(NAV_DATA_OP.[V_NO] as NVARCHAR) = CAST(OMS_DATA.[COD_BOB_SUPPLIER] AS NVARCHAR) 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''Vendor'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

--print @QUERY_OMS_1
			EXEC(@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
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
(
SELECT [ID_COMPANY],[OMS_Vendor_No],ROW_NUMBER() over(partition by id_company,[OMS_Vendor_No] order by cod_timestamp desc) as rownum
FROM [AIG_Nav_Jumia_Reconciliation].[dbo].OMS_RECONCILIATION_VENDORS
)
DELETE FROM CTE WHERE cte.rownum>1


GO
