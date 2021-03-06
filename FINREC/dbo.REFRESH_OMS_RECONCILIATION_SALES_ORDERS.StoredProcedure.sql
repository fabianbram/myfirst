USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_SALES_ORDERS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_SALES_ORDERS]
AS
-- drop table OMS_RECONCILIATION_SALES_ORDERS
DECLARE @CUT_OFF_DATE NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(150);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_OMS_2 NVARCHAR(MAX);
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

SET @PRINT_MSG = 'OMS_RECONCILIATION_SALES_ORDERS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT9];

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
	WHERE ACTIVE = 1
	ORDER BY [ORDER] ASC;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_SALES_ORDERS';
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
			
	
		WHILE 1=1
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
				  SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(' + @INC_COL + '),''1900-01-01 00:00:00'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
				  SET @THRESHOLD = N'@EXTRACT_THRESHOLD varchar(100) OUTPUT';			
				  -- get date for current country
				  EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
			  END
			  ELSE
			  BEGIN	
				  SET @THRESHOLD = '1900-01-01 00:00:00';	
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END
			-- DROP TABLE OMS_RECONCILIATION_SALES_ORDERS
			SET @BATCH_COUNTER = 1000000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT  OMS_DATA.ID_COMPANY AS ID_COMPANY
				  ,OMS_DATA.COD_ORDER_NR AS OMS_SO_No
				  ,OMS_DATA.COD_DATE AS OMS_Creation_Date
				  ,OMS_DATA.STATUS AS Sales_Order_Status
				  ,OMS_DATA.COD_CUSTOMER AS OMS_Customer_No')
		   SET @QUERY_OMS_2 = ',OMS_DATA.countretail as OMS_Count_Retail_Items
				  ,OMS_DATA.countmarketplace as OMS_Count_Marketplace_Items
				  ,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
				  ,RABO_DATA.id_message AS OMS_Message_ID		
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,RABO_DATA.response_message AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] AS Nav_Message_Status
				  ,NAV_DATA.[Error Message] AS Nav_Error_Message
				  ,CASE WHEN NAV_DATA_OP.SO_NO is null then ''False'' else ''True'' END AS Nav_Sales_Order_Created
				  ,OMS_DATA.COD_TIMESTAMP
				  ,YEAR(OMS_DATA.COD_DATE) AS OMS_Creation_Year		
				   ' + @INSERT_INTO + '
			FROM OPENQUERY([BI-DWH-JUMIA], ''SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
															 ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY															  
															 ,PSO.COD_ORDER_NR
															 ,PSO.COD_CUSTOMER
															 ,PSO.COD_DATE
															 ,PSO.COD_DATE COD_TIMESTAMP
															 ,PSOSH.STATUS
															 ,sum(case when psoi.MTR_IS_MARKETPLACE=0 THEN 1 ELSE 0 END) as countretail
															 ,sum(case when psoi.MTR_IS_MARKETPLACE=1 THEN 1 ELSE 0 END) as countmarketplace
															FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order] AS PSO
															JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order_ITEM] as PSOI 
															  ON PSO.COD_ORDER_NR=PSOI.COD_ORDER_NR
															---- Valid and Invalid Order nr logic encapsulated in the following join  -------
															LEFT JOIN( select CASE WHEN MAX(STATUS)=1 THEN ''''Valid'''' ELSE ''''Invalid'''' END as Status
																			  ,COD_ORDER_NR 
																	   FROM(select ROW_NUMBER()OVER(PARTITION BY s.COD_ORDER_NR,s.COD_SALES_ORDER_ITEM ORDER BY s.COD_DATE DESC) as r
																					,CASE WHEN s.COD_SALES_ORDER_ITEM_STATUS NOT IN (2,6,9,10,19,29,34) THEN 1 ELSE -1 END AS STATUS
																					,s.COD_ORDER_NR
																					,s.COD_SALES_ORDER_ITEM
																					,i.MTR_IS_MARKETPLACE
																					,s.COD_SALES_ORDER_ITEM_STATUs
																					FROM [AIG_JUMIA_KE_STG].[dbo].[PRE_SALES_ORDER_ITEM_STATUS_HISTORY] as s
																					LEFT JOIN [AIG_JUMIA_KE_STG].[dbo].[PRE_Sales_Order_ITEM] as i
																						  ON s.COD_SALES_ORDER_ITEM=i.COD_SALES_ORDER_ITEM AND i.MTR_IS_MARKETPLACE=0
																					WHERE i.COD_SYSTEM=''''OMS'''' 
																			) as p
																		where p.r=1
																		GROUP BY COD_ORDER_NR
																	 ) AS PSOSH 
																  ON PSO.COD_ORDER_NR=PSOSH.COD_ORDER_NR
															WHERE PSOI.COD_SYSTEM = ''''OMS'''' -- >ONLY ORDERS EXISTING IN OMS SHOULD BE USED
															 AND PSO.COD_DATE > CAST(''''' + @THRESHOLD + ''''' AS DATETIME2) -- > AUDIT FIELD IS COD_DATE_TIME
															 AND PSO.COD_DATE > CAST(''''' + @CUT_OFF_DATE + ''''' AS DATE)
															GROUP BY 
																PSO.COD_ORDER_NR
																,PSO.COD_CUSTOMER
																,PSO.COD_DATE
																,PSOSH.STATUS																												 
															'') AS OMS_DATA' ;



		SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENT9] AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.[COD_ORDER_NR] 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT ID_COMPANY,
												 SO.[No_] as SO_NO							  
					    FROM [dbo].[Sales Orders] AS SO									
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[SO_NO] = OMS_DATA.[COD_ORDER_NR] 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

			SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''SalesOrder'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

	    -- select @QUERY_OMS_1, @QUERY_OMS_2, @QUERY_RABBIT, @QUERY_NAV
			EXEC(@QUERY_OMS_1 + @QUERY_OMS_2 + @QUERY_RABBIT+ @QUERY_NAV);
			SET @ROWCOUNT = @@ROWCOUNT
			IF @ROWCOUNT<@BATCH_COUNTER/3 BREAK; /*BREAK WHILE 1=1 LOOP*/
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;



GO
