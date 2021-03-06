USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_BOB_RECONCILIATION_CUSTOMERS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[REFRESH_BOB_RECONCILIATION_CUSTOMERS]
AS
-- drop table OMS_RECONCILIATION_VENDORS
DECLARE @CUT_OFF_DATE2 NVARCHAR(50),
@PRINT_MSG NVARCHAR(200),
@QUERY_OMS_1 NVARCHAR(MAX),
@QUERY_NAV NVARCHAR(MAX),
@QUERY_RABBIT NVARCHAR(MAX),
@COUNTRY NVARCHAR(150),
@COUNTRY_CODE NVARCHAR(50),
@SHORT_COUNTRY_CODE NVARCHAR(50),
@INC_COL NVARCHAR(50),
@TABLE_TO_CREATE NVARCHAR(400),
@TABLE_TO_CREATE_SCHEMA NVARCHAR(150),
@BATCH_COUNTER INT,
@ROWCOUNT INT,
@MAXDATE as nvarchar(60)

--PRINT ('Deleting rows in BOB_RECONCILIATION_CUSTOMERS table...')
--DELETE FROM AIG_Nav_Jumia_Reconciliation.dbo.BOB_RECONCILIATION_CUSTOMERS;
--PRINT (CAST(@@ROWCOUNT as varchar) + ' rows deleted')

--SET @PRINT_MSG = '== PROCESSING RABBIT MESSAGES ==' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENTCUST_INC];

--SET @PRINT_MSG = '== PROCESSING NAVISION MESSAGES == ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];


-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE2
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1 ORDER BY [ORDER] ASC;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'AIG_Nav_Jumia_Reconciliation.dbo.BOB_RECONCILIATION_CUSTOMERS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2
		

	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		DECLARE @INSERT NVARCHAR(200), @INSERT_INTO NVARCHAR(200);
		SET @PRINT_MSG = 'PROCESSING COUNTRY: ' + @COUNTRY_CODE
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
		
		WHILE 1=1
		BEGIN
			 
			  IF OBJECT_ID('AIG_Nav_Jumia_Reconciliation.dbo.BOB_RECONCILIATION_CUSTOMERS') is not null
			  BEGIN
				  DECLARE @SQLSTRING as NVARCHAR(1000)
				  SET @SQLSTRING = N'SELECT @EDATE=isnull(MAX(created_at),''1900-01-01'') FROM '+@TABLE_TO_CREATE+' WHERE ID_COMPANY = '''+@COUNTRY_CODE+''';'
				  SET @MAXDATE = N'@EDATE varchar (400) OUTPUT'
				  EXEC sp_executesql @SQLSTRING,@MAXDATE, @EDATE = @MAXDATE OUTPUT;

				  SET @INSERT = 'INSERT INTO ' +  @TABLE_TO_CREATE;
				  SET @INSERT_INTO='';		
			  END
			  ELSE
			  BEGIN	
				  SET @MAXDATE = '1900-01-01'
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END

			SET @BATCH_COUNTER = 500000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 'SELECT OMS_DATA.ID_Company
					,OMS_DATA.id_customer as Bob_Customer_No					
					,(Case when RABO_DATA.[COD_TIMESTAMP] is not null then ''True'' else ''False'' end) AS BOB_Message_Created 
					,RABO_DATA.[message_id] AS BOB_Message_ID	
					,RABO_DATA.status AS RabbitMQ_Status
				    ,RABO_DATA.error AS RabbitMQ_Error_Message					
					,NAV_DATA.[Status] as Nav_Message_Status
					,NAV_DATA.[Error Message] as Nav_Error_Message
					,CASE WHEN NAV_DATA_OP.[C_NO] IS NULL THEN ''False'' ELSE ''True'' END as ''Nav_Customer_Created''					
					,OMS_DATA.created_at 
				  ' + @INSERT_INTO + '
				  FROM openquery([BI-BOB_LIVE_' + @SHORT_COUNTRY_CODE + '],''select	''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
																					,id_customer
																					,created_at
																			 from customer
																			 where created_at > ''''' + @MAXDATE + '''''
																			 order by created_at asc
																			
																			 limit ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
																		   ''
								) AS OMS_DATA
				  ');
SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENTCUST] AS RABO_DATA 
				   ON RABO_DATA.fk_erp_navision_entity = OMS_DATA.[id_customer] 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY,
												 C.[No_] as C_NO 												 								  
					    FROM [dbo].[Customers] AS C						
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[C_NO] = cast(OMS_DATA.[id_customer] as nvarchar) 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''Customer'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[message_id] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

			--SELECT @QUERY_OMS_1,@QUERY_RABBIT,@QUERY_NAV
			EXEC(@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
			SET @ROWCOUNT = @@ROWCOUNT
			IF @ROWCOUNT<@BATCH_COUNTER/4 BREAK;

		  -- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;



GO
