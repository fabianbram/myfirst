USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_PURCHASE_RETURNS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_PURCHASE_RETURNS]
AS


DECLARE @CUT_OFF_DATE NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(150);
DECLARE @QUERY_OMS NVARCHAR(MAX);
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

SET @PRINT_MSG = 'OMS_RECONCILIATION_PURCHASE_RETURNS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EC_MA is an exception and should not be processedin the next procedure [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT7]
--filter was also added in [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT7]
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT7];

SET @PRINT_MSG = '==== PROCESSING NAVISION MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];

-- get all countries from config table
--EC_MA is an exception and should not process this entity
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE
		, INCREMENTAl_COL
		, REPROCESS_ALL
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1 and ID_COMPANY != 'EC_MA' ORDER BY [ORDER] ASC;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'AIG_Nav_Jumia_Reconciliation.dbo.OMS_RECONCILIATION_PURCHASE_RETURNS';
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
		DECLARE @THRESHOLD NVARCHAR(50);		

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
			SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(' + @INC_COL + '),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
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
			  
		-- QUERY HERE
		SET @BATCH_COUNTER = 1000; 
		
		SET @QUERY_OMS =(@INSERT +  char(13) + char(10) + '
		SELECT		 OMS_DATA.ID_Company
					,OMS_DATA.return_number as Purchase_Return_Order_No
					,OMS_DATA.created_at as Creation_Date
					,OMS_DATA.fk_supplier as Vendor_No
					,OMS_DATA.Vendor_Name as Vendor_Name
					,OMS_DATA.Count_Consignment AS OMS_Count_Consignment_Items
					,OMS_DATA.Count_Outright AS OMS_Outright_Items
					,OMS_DATA.Count_Marketplace AS OMS_Count_Marketplace_Items
					,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
					,RABO_DATA.[id_message] AS OMS_Message_ID	
					,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				    ,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message	
					,OMS_DATA.OMS_Count_Items_Returned AS OMS_Count_Items_Returned
					,OMS_DATA.OMS_Purchase_Return_Amount_Excl_VAT
					,OMS_DATA.OMS_Purchase_Return_Amount_Incl_VAT
					,OMS_DATA.COD_TIMESTAMP 
					,NAV_DATA.[Status] as Nav_Message_Status
					,NAV_DATA.[Error Message] as Nav_Error_Message					
					,CASE WHEN NAV_DATA_OP.[PO_OMS] IS NULL THEN ''False'' ELSE ''True'' END as Nav_Purchase_Return_Posted
					,NAV_DATA_OP.PPRS_ITEMS as Nav_Count_Items_Returned
					,NAV_DATA_OP.[Purchase_Return_Amount_Excl_VAT]
					,NAV_DATA_OP.[Purchase_Return_Amount_Incl_VAT]		
					,YEAR(OMS_DATA.created_at) as Creation_Year
					' + @INSERT_INTO + '	
		FROM(
	  SELECT  * FROM OPENQUERY([BI-DWH-JUMIA], ''select * from(SELECT DS_INT.*, row_number() over(order by DS_INT.COD_TIMESTAMP ASC) as rn
			from (SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '   
			''''' + @COUNTRY_CODE + ''''' as ID_COMPANY,
			RO.id_supplier_return,			
			RO.return_number,			
			RO.created_at,
			RO.fk_supplier,
			ROP.id_supplier_return_package,
			ISNULL(SUP.DSC_SUPPLIER_NAME,''''N/A'''') as Vendor_Name,													
			sum(CASE WHEN CT.DSC_CONTRAT_TYPE_NAME = ''''Consignment'''' THEN 1 ELSE 0 END) as Count_Consignment,
			sum(CASE WHEN CT.DSC_CONTRAT_TYPE_NAME = ''''Outright'''' THEN 1 ELSE 0 END) as Count_Outright,
			sum(CASE WHEN CT.DSC_CONTRAT_TYPE_NAME = ''''Marketplace'''' THEN 1 ELSE 0 END) as Count_Marketplace,											
			sum(1) as OMS_Count_Items_Returned,
			sum(ISNULL(POI.COST,0)) as OMS_Purchase_Return_Amount_Excl_VAT,
			sum((ISNULL(POI.COST,0)+ISNULL(POI.TAX_AMOUNT,0))) as OMS_Purchase_Return_Amount_Incl_VAT,
			CAST(RO.UPDATED_AT AS DATETIME) as COD_TIMESTAMP');													
SET @QUERY_OMS_2 =(char(13) + char(10) +' FROM (select * from [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_NAV_SUPPLIER_RETURN] where fk_supplier_return_status = 6) RO
	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_NAV_SUPPLIER_RETURN_PACKAGE] as ROP
	  ON RO.return_number = LEFT(ROP.package_number,13)
	  JOIN (select * from [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_NAV_SUPPLIER_RETURN_ITEM] where fk_supplier_return_item_status = 9) ROI
	  ON RO.id_supplier_return = ROI.fk_supplier_return  
	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SUPPLIER] SUP
	  ON RO.fk_supplier = SUP.COD_SUPPLIER AND SUP.COD_SYSTEM = ''''OMS''''
	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS] PO
	  ON (select top 1 fk_purchase_order from [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].PRE_NAV_SUPPLIER_RETURN_ITEM where fk_purchase_order=ROI.fk_purchase_order) = PO.COD_PURCHASE_ORDER
	  LEFT JOIN (SELECT POID.* FROM (SELECT	COD_PURCHASE_ORDER
			,COD_SUPPLIER_PRODUCT
			,COST
			,TAX_AMOUNT
			,ROW_NUMBER() OVER(PARTITION BY COD_PURCHASE_ORDER,COD_SUPPLIER_PRODUCT ORDER BY COD_SALES_ORDER_ITEM DESC) as RANK_ORD
	  FROM  [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].dbo.PRE_PURCHASE_ORDERS_ITEM AS ROI 
	  ) POID WHERE POID.RANK_ORD = 1) POI
	  ON POI.COD_PURCHASE_ORDER = ROI.fk_purchase_order 
	  AND POI.COD_SUPPLIER_PRODUCT = ROI.fk_supplier_product											 
	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS_CONTRACT_TYPE] CT 
	  ON CT.COD_PURCHASE_ORDER_CONTRACT_TYPE = PO.COD_PURCHASE_ORDER_CONTRACT_TYPE											
	  WHERE RO.UPDATED_AT > CAST(''''' + @CUT_OFF_DATE + ''''' AS DATE) 
			AND RO.UPDATED_AT > ''''' + @THRESHOLD + '''''
			GROUP BY 
			RO.id_supplier_return,
			RO.created_at,
			RO.return_number,
			RO.fk_supplier,
			SUP.DSC_SUPPLIER_NAME,
			RO.UPDATED_AT,
			ROP.id_supplier_return_package
	  ) DS_INT ) aux	
				  where aux.rn <= ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '	
							 '')) AS OMS_DATA');

SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT7 AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.id_supplier_return_package 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT 
												 PPRS.[No_] AS PO_OMS												
												 ,PPRS.id_company
												 ,PPRS.[No_ of Items on Purchase Return] as PPRS_ITEMS
												 ,PPRS.[Purchase Return Amount Excl_ VAT] AS [Purchase_Return_Amount_Excl_VAT]
												 ,PPRS.[Purchase Return Amount Incl_ VAT] AS [Purchase_Return_Amount_Incl_VAT]						  
					    FROM [dbo].[Posted Purchase Return Shipments] AS PPRS										
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PO_OMS] = OMS_DATA.return_number
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''PurchaseReturnOrder'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

		EXEC(@QUERY_OMS+@QUERY_OMS_2+ @QUERY_RABBIT + @QUERY_NAV);
		--select @QUERY_OMS,@QUERY_OMS_2, @QUERY_RABBIT , @QUERY_NAV;
		SET @ROWCOUNT = @@ROWCOUNT

		--PRINT(@QUERY_NAV)
		-- PRINT LAST LOADED COUNT
		SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
			
    END

		FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;

GO
