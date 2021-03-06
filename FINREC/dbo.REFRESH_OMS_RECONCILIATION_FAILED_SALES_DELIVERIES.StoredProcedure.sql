USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_FAILED_SALES_DELIVERIES]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_FAILED_SALES_DELIVERIES]
AS
-- drop table OMS_RECONCILIATION_FAILED_SALES_DELIVERIES
DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
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


SET @PRINT_MSG = 'OMS_RECONCILIATION_FAILED_SALES_DELIVERIES ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT11];

SET @PRINT_MSG = '==== PROCESSING NAVISION MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];

-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE2
		, INCREMENTAl_COL
		, REPROCESS_ALL
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1
	ORDER BY [ORDER] ASC;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_FAILED_SALES_DELIVERIES';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
		
	SET @COUNTER = 1;
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		DECLARE @MAX_DATE NVARCHAR(50);
		DECLARE @INSERT NVARCHAR(250);
		DECLARE @INSERT_INTO NVARCHAR(250);
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
				  SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(OMS_Failed_Delivery_Date),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
				  SET @THRESHOLD = N'@EXTRACT_THRESHOLD varchar(100) OUTPUT';			
				  -- get date for current country
				  EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
			  END
			  ELSE
			  BEGIN	
				  SET @THRESHOLD = '1900-01-01';	
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END
			-- DROP TABLE OMS_RECONCILIATION_FAILED_SALES_DELIVERIES
			SET @BATCH_COUNTER = 2000000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT  OMS_DATA.ID_COMPANY AS ID_Company
				  ,OMS_DATA.package_number AS OMS_Package_No
				  ,OMS_DATA.created_at AS OMS_Failed_Delivery_Date				  
				  ,OMS_DATA.order_nr AS OMS_SO_No
				  ,OMS_DATA.bob_id_customer AS OMS_Customer_No				  
				  ,OMS_DATA.OMS_Count_Retail_Items
				  ,OMS_DATA.OMS_Count_Marketplace_Items');

		   SET @QUERY_OMS_2 = ',CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
				  ,RABO_DATA.id_message AS OMS_Message_ID		
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] AS Nav_Message_Status
				  ,NAV_DATA.[Error Message] AS Nav_Error_Message				  
				  ,CASE WHEN NAV_DATA_OP.SO_NO is null then ''False'' else ''True'' END AS Nav_Sales_Shipment_Posted
				  ,NAV_DATA_OP.nritems AS Nav_Count_Shipped_Items			
				  ,OMS_DATA.COD_TIMESTAMP	
				  ,YEAR(OMS_DATA.FAILED_DATE) AS OMS_Failed_Delivery_Year	
				   ' + @INSERT_INTO + '
				   FROM OPENQUERY([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],''SELECT ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
																				     ,p.package_number
																					 ,max(ifnull(soish.created_at,-1)) as created_at
																					 ,so.order_nr
																					 ,so.bob_id_customer
																					 ,SUM(CASE WHEN soi.is_marketplace =0 THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
			--																		 ,SUM(CASE soi.is_marketplace THEN 1 ELSE 0 END) as OMS_Count_Marketplace_Items		
																			  FROM ims_sales_order_item as soi
																			  JOIN ims_sales_order_item_status_history as soish
																					ON soish.fk_sales_order_item = soi.id_sales_order_item
																			  JOIN oms_package_item as pi
																					on pi.fk_sales_order_item = soi.id_sales_order_item
																			  JOIN oms_package as p
																					on p.id_package = pi.fk_package
																			  JOIN ims_sales_order as so
																					ON soi.fk_sales_order = so.id_sales_order
																			  WHERE soish.fk_sales_order_item_status=44
																			  and soish.created_at > ''''' + @THRESHOLD + '''''
																			  and soish.created_at > ''''' + @CUT_OFF_DATE2+ '''''
																			  order by soish.created_at asc 
																			''
								 ) as OMS_DATA
				   
				   ';






	
			--FROM( SELECT * FROM OPENQUERY([BI-DWH-JUMIA], ''select * from(SELECT DS_INT.*
			--													   , row_number() over(order by DS_INT.COD_TIMESTAMP ASC) as rn
			--												from (SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
			--												 ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY															
			--												,NAV_PK.COD_TRACKING_NUMBER as COD_PACKAGE																														
			--												,max(PP.FAILED_DATE) as FAILED_DATE	
			--												,PSO.COD_ORDER_NR
			--												,PSO.COD_CUSTOMER
			--												,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
			--												,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN 1 ELSE 0 END) as OMS_Count_Marketplace_Items																																												
			--												,PSO.COD_TIMESTAMP	
			--											 FROM (select * from [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order_Item] where COD_SYSTEM = ''''OMS'''' ) AS PSOI
			--														   JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order] AS PSO
			--														   ON PSO.COD_ORDER_NR = PSOI.COD_ORDER_NR
			--											LEFT JOIN (
			--											 select * from (SELECT  PSOISH.COD_DATE,PSOISH.COD_SALES_ORDER_ITEM AS COD_SALES_ORDER_ITEM_OMS,prep.COD_PACKAGE,preph.COD_DATE as FAILED_DATE,
			--											 row_number() over(partition by PSOISH.COD_SALES_ORDER_ITEM_STATUS,PSOISH.COD_SALES_ORDER_ITEM order by PSOISH.COD_DATE desc) rank
			--											  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM_STATUS_HISTORY] AS PSOISH
			--											  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE_ITEM] prep ON PSOISH.COD_SALES_ORDER_ITEM = prep.[COD_SALES_ORDER_ITEM_OMS]
			--											  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE_STATUS_HISTORY] AS preph ON prep.COD_PACKAGE = preph.COD_PACKAGE 
			--											  WHERE PSOISH.COD_SALES_ORDER_ITEM_STATUS = 44 AND PSOISH.COD_SYSTEM = ''''OMS''''
			--											   ) a where rank = 1 ) AS PP  
			--											ON PP.COD_SALES_ORDER_ITEM_OMS = PSOI.COD_SALES_ORDER_ITEM               
			--														   JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].V_PRE_OMS_PACKAGE NAV_PK     
			--														   ON NAV_PK.COD_PACKAGE = PP.COD_PACKAGE                 
			--														   	WHERE PSO.COD_TIMESTAMP > ' + @THRESHOLD + '
			--																	AND PSO.COD_TIMESTAMP > ' + @CUT_OFF_DATE_BI + '
			--														   group by NAV_PK.COD_TRACKING_NUMBER,
			--															NAV_PK.COD_PACKAGE
			--														   ,PSO.COD_ORDER_NR																	               
			--														   ,PSO.COD_CUSTOMER
			--														   ,PSO.COD_TIMESTAMP
			--											 ) DS_INT ) aux	
			--												where aux.rn <= ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
			--												'')) AS OMS_DATA' ;

		SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT11 AS RABO_DATA 
				   ON RABO_DATA.id_related_entity = OMS_DATA.package_number
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY
												 ,CAST([No_] as nvarchar) as SO_NO
												 ,[No_ of Items on Sales Shipment] as NrItems						  
					    FROM [dbo].[Posted Sales Shipments] AS SO									
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
						ON NAV_DATA_OP.[SO_NO] = OMS_DATA.package_number 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY
						');


SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''SalesOrderDelivery'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY
						');
				  
									

			EXEC(@QUERY_OMS_1+@QUERY_OMS_2+ @QUERY_RABBIT +@QUERY_NAV);
			SET @ROWCOUNT = @@ROWCOUNT
			
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;




GO
