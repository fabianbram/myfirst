USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_SALES_SHIPMENTS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_SALES_SHIPMENTS]
AS
-- drop table REFRESH_OMS_RECONCILIATION_SALES_SHIPMENTS
DECLARE @CUT_OFF_DATE2 AS NVARCHAR(150);
DECLARE @PRINT_MSG NVARCHAR(400);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_OMS_2 NVARCHAR(MAX);
DECLARE @QUERY_NAV NVARCHAR(MAX);
DECLARE @QUERY_RABBIT NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @INC_COL NVARCHAR(50);
DECLARE @REP_ALL bit;
DECLARE @TABLE_TO_CREATE NVARCHAR(200);
DECLARE @TABLE_TO_CREATE_SCHEMA NVARCHAR(200);
DECLARE @COUNTER INT;
DECLARE @BATCH_COUNTER INT;
DECLARE @ROWCOUNT INT;




SET @PRINT_MSG = 'OMS_RECONCILIATION_SALES_SHIPMENTS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT10];

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
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_SALES_SHIPMENTS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
		
	SET @COUNTER = 1;
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		WHILE 1=1
		BEGIN

		DECLARE @MAX_DATE NVARCHAR(50);
		DECLARE @INSERT NVARCHAR(250);
		DECLARE @INSERT_INTO NVARCHAR(250);
		DECLARE @THRESHOLD NVARCHAR(100);
			
		SET @PRINT_MSG = 'PROCESSING COUNTRY: ' + @COUNTRY_CODE
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
			
			
		
			  
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
			-- DROP TABLE REFRESH_OMS_RECONCILIATION_SALES_SHIPMENTS
			SET @BATCH_COUNTER = 700000; /*Mudei o Batch para 200.000 porque na NG estava sempre a expirar o tempo de ligação(experimentar com 700.000 na proxima ronda*/	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT  
				  OMS_DATA.ID_COMPANY AS ID_Company
				  ,OMS_DATA.COD_PACKAGE AS OMS_Sales_Package_No
				  ,OMS_DATA.COD_DATE AS OMS_Shipment_Date				  
				  ,OMS_DATA.COD_ORDER_NR AS OMS_SO_No
				  ,OMS_DATA.COD_CUSTOMER AS OMS_Customer_No				  
				  ,OMS_DATA.OMS_Count_Retail_Items
				  ,OMS_DATA.OMS_Count_Marketplace_Items
				  ,YEAR(OMS_DATA.COD_DATE) AS OMS_Shipment_Year
				 ');

		   SET @QUERY_OMS_2 = ',CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
				  ,RABO_DATA.id_message AS OMS_Message_ID		
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] AS Nav_Message_Status
				  ,NAV_DATA.[Error Message] AS Nav_Error_Message
				  ,CASE WHEN NAV_DATA_OP.SO_NO IS NOT NULL THEN ''True'' ELSE ''False'' END AS Nav_Sales_Shipment_Posted
				  ,NAV_DATA_OP.nritems AS Nav_Count_Shipped_Items				
				  ,OMS_DATA.COD_TIMESTAMP		
				   ' + @INSERT_INTO + '
				   FROM OPENQUERY[BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],''SELECT ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
																				   ,p.package_number
																				   ,ifnull(p.created_at,-1) as created_at
																				   ,so.order_nr
																				   ,so.bob_id_customer
																				   ,sum(case when soi.is_marketplace=0 then 1 else 0 end) as OMS_Count_Retail_Items
																				   ,SUM(CASE WHEN soi.is_marketplace=0 THEN 1 ELSE 0 END) as OMS_Count_Marketplace_Items	
																			  FROM ims_sales_order_item as soi
																			  JOIN oms_package_item as pi
																					on pi.fk_sales_order_item = soi.id_sales_order_item
																			  JOIN oms_package as p
																					on p.id_package = pi.fk_package
																			  JOIN oms_package_history as ph
																					on ph.id_package=p.id_package
																			  JOIN ims_sales_order as so
																					ON soi.fk_sales_order = so.id_sales_order
																			  and p.created_at > ''''' + @THRESHOLD + '''''
																			  and p.created_at > ''''' + @CUT_OFF_DATE2+ '''''
																			  and ph.fk_package_status=4
																			''
								 ) as OMS_DATA

				   ';



--FROM OPENQUERY([BI-DWH-JUMIA],''SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 																														
--''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
--,NAV_PK.COD_TRACKING_NUMBER as COD_PACKAGE														
--,max(PP.COD_DATE) as COD_DATE	
--,PSO.COD_ORDER_NR
--,PSO.COD_CUSTOMER
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN 1 ELSE 0 END) as OMS_Count_Marketplace_Items																														
--,PSO.COD_TIMESTAMP
--FROM (SELECT MTR_IS_MARKETPLACE,COD_SALES_ORDER,COD_ORDER_NR,COD_SALES_ORDER_ITEM FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order_Item] WHERE COD_SHIPPING_TYPE IS NOT NULL and COD_SYSTEM=''''OMS'''' ) AS PSOI
--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE_ITEM] AS PPI
--	ON PPI.COD_SALES_ORDER_ITEM_OMS = PSOI.COD_SALES_ORDER_ITEM
--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE] AS PP
--	ON PP.COD_PACKAGE = PPI.COD_PACKAGE AND PP.COD_SYSTEM=''''OMS'''' 
--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE_STATUS_HISTORY] AS preph 
--	ON PP.COD_PACKAGE = preph.COD_PACKAGE AND preph.COD_PACKAGE_STATUS = 4	
--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order] AS PSO
--ON PSO.COD_ORDER_NR = PSOI.COD_ORDER_NR                
--left JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].V_PRE_OMS_PACKAGE_TB AS NAV_PK     
--ON NAV_PK.COD_PACKAGE = PP.COD_PACKAGE    
--WHERE PSO.COD_TIMESTAMP > ' + @THRESHOLD + '
--AND PSO.COD_TIMESTAMP > ' + @CUT_OFF_DATE2 + '
--group by NAV_PK.COD_TRACKING_NUMBER
--,NAV_PK.COD_PACKAGE
--   ,PP.COD_DATE 
--   ,PSO.COD_ORDER_NR
--   ,PSO.COD_CUSTOMER
--   ,PSO.COD_TIMESTAMP
--order by PSO.COD_TIMESTAMP asc										 
--'') AS OMS_DATA' ;


		SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT10 AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.COD_PACKAGE 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY
												 ,[No_] as SO_NO
												 ,[No_ of Items on Sales Shipment] as NrItems																					  
					    FROM [dbo].[Posted Sales Shipments] AS SO									
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
						ON NAV_DATA_OP.[SO_NO] = CAST(OMS_DATA.[COD_PACKAGE] as nvarchar)
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY
						');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
		LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''SalesShipment'') AS NAV_DATA 
		ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
			AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
				');	
	  

			EXEC(@QUERY_OMS_1+@QUERY_OMS_2+@QUERY_RABBIT+@QUERY_NAV)
			SET @ROWCOUNT = @@ROWCOUNT
			IF @ROWCOUNT<@BATCH_COUNTER/3 BREAK;
				-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;



GO
