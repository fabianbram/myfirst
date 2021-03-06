USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_PO_RECEIPTS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_PO_RECEIPTS]
AS

--Countries : JM_EG; EC_NG; EC_MA; EC_KE; EC_IC; JD_PK 
-- DROP TABLE OMS_RECONCILIATION_PO_RECEIPTS;

DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(150);
DECLARE @QUERY_OMS NVARCHAR(MAX);
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
DECLARE @UPDATENAV NVARCHAR(MAX);

--SET @PRINT_MSG = 'OMS_RECONCILIATION_PO_RECEIPTS ==== PROCESSING RABBIT MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT5];

--SET @PRINT_MSG = '==== PROCESSING NAVISION MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];

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
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_PO_RECEIPTS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
		
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
			SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(OMS_PO_Receipt_Creation_Date),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
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
			  
SET @BATCH_COUNTER = 1000000;

SET @QUERY_OMS = (@INSERT +  char(13) + char(10) + 
'SELECT  OMS_DATA.ID_COMPANY AS N''ID_COMPANY''				  
		,OMS_DATA.id_delivery_receipt AS N''OMS_PO_Receipt_No''
		,CONCAT(YEAR(OMS_DATA.created_at),''/'',datepart(mm,OMS_DATA.created_at),''/'',day(OMS_DATA.created_at)) AS N''OMS_PO_Receipt_Creation_Date''
		,OMS_DATA.fk_purchase_order N''OMS_PO_ID''
		,OMS_DATA.po_number AS N''OMS_PO_No''
		,OMS_DATA.bob_id_supplier AS N''OMS_VENDOR_No''
		,OMS_DATA.suppliername AS N''OMS_Vendor_Name''
		,OMS_DATA.contractname AS N''OMS_Contract_Type''
		,OMS_DATA.countreceipts AS N''OMS_Count_items_Received''
		,OMS_DATA.EXCL_VAT1 AS N''OMS_Receipt_Amount_Excl_VAT''
		,OMS_DATA.INCL_VAT1 AS N''OMS_Receipt_Amount_Incl_VAT''
		,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN N''False'' ELSE N''True'' END AS OMS_Message_Created 
		,RABO_DATA.[id_message] AS OMS_Message_ID				
		,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
		,RABO_DATA.response_message AS RabbitMQ_Error_Message
		,NAV_DATA.[Status] as N''Nav_Message_Status''
		,NAV_DATA.[Error Message] as N''Nav_Error_Message''
		,CASE WHEN NAV_DATA_OP.PO_OMS IS NULL THEN ''False'' else ''True'' END as N''Nav_PO_Receipt_Posted''
		,NAV_DATA_OP.PO_OMS AS Nav_PO_Receipt
		,NAV_DATA_OP.CountItems as N''Nav_Count_Items_Posted''
		,NAV_DATA_OP.EXCL_VAT AS N''Nav_Receipt_Amount_Excl_Vat''
		,NAV_DATA_OP.INCL_VAT AS N''Nav_Receipt_Amount_Incl_Vat''				  
		,YEAR(OMS_DATA.created_at) AS OMS_PO_Receipts_Creation_Year
		' + @INSERT_INTO + ' 
 FROM OPENQUERY ([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],''select ''''' + @COUNTRY_CODE + ''''' as Id_company 
																	,dr.id_delivery_receipt
																	,dr.created_at
																	,dr.fk_purchase_order
																	,po.po_number
																	,s.bob_id_supplier 
																	,s.name as suppliername
																	,poct.name as contractname
																	,count(dri.fk_purchase_order_item) as countreceipts
																	,Cast(sum(ifnull(poi.cost,0) * ifnull(poi.quantity,0)) as decimal (13,2)) As EXCL_VAT1
																	,Cast(sum(ifnull(poi.cost,0) * ifnull(poi.quantity,0) + ifnull(poi.tax_amount,0)) as decimal (13,2)) As INCL_VAT1
																	
															FROM ims_purchase_order as po
															JOIN wms_delivery_receipt as dr
																on po.id_purchase_order = dr.fk_purchase_order
															JOIN wms_delivery_receipt_item as dri
																on dri.fk_delivery_receipt=id_delivery_receipt
															JOIN ims_purchase_order_item as poi	
																on poi.id_purchase_order_item = dri.fk_purchase_order_item
															LEFT JOIN ims_supplier as s
																on s.id_supplier=po.fk_supplier
															LEFT JOIN ims_purchase_order_contract_type as poct
																on poct.id_purchase_order_contract_type = po.fk_purchase_order_contract_type
															WHERE dr.created_at > ''''' + @CUT_OFF_DATE2 + ''''' and dr.created_at > ''''' + @THRESHOLD + ''''' 
															GROUP BY 
																 dr.id_delivery_receipt
																,dr.created_at
																,dr.fk_purchase_order
																,po.po_number
																,s.bob_id_supplier 
																,s.name 
																,poct.name 
															ORDER BY dr.created_at	asc
															limit ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
															''
				) AS OMS_DATA	
						
				 ');



--FROM OPENQUERY([BI-DWH-JUMIA], 
--	  ''select * from(SELECT DS_INT.*, row_number() over(order by DS_INT.COD_TIMESTAMP ASC) as rn
--	  from (SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
--	  ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
--	  ,CAST(PDR.COD_DELIVERY_RECEIPT as NVARCHAR) COD_DELIVERY_RECEIPT
--	  ,PDR.COD_DATE
--	  ,PDR.COD_PURCHASE_ORDER
--	  ,PPO.COD_PO_NUMBER
--	  ,COALESCE(PS.COD_BOB_SUPPLIER,PPO.COD_SUPPLIER) as COD_BOB_SUPPLIER
--	  ,COALESCE(PS.DSC_SUPPLIER_NAME_EN,PPO.DSC_SUPPLIER_CONTACT_NAME) AS DSC_SUPPLIER_NAME_EN
--	  ,PPOCT.DSC_CONTRAT_TYPE_NAME
--	  ,COUNT(PDRI.fk_delivery_receipt) AS QUANTITY_PDRI
--	  ,SUM(ISNULL(PPOI.COST,0) * ISNULL(PPOI.QUALITY,1)) AS EXCL_VAT1
--	  ,SUM((ISNULL(PPOI.TAX_AMOUNT,0)+ISNULL(PPOI.COST,0))*ISNULL(PPOI.QUALITY,1)) AS INCL_VAT1
--	  ,PDR.COD_TIMESTAMP
--	  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_DELIVERY_RECEIPT] AS PDR
--	  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_NAV_DELIVERY_RECEIPT_ITEM] AS PDRI
--	  ON PDR.COD_DELIVERY_RECEIPT = PDRI.fk_delivery_receipt AND PDR.COD_SYSTEM = ''''OMS''''
--	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS] AS PPO
--	  ON PDR.COD_PURCHASE_ORDER = PPO.COD_PURCHASE_ORDER 
--	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS_ITEM] AS PPOI
--	  ON PPOI.COD_PURCHASE_ORDER_ITEM = PDRI.fk_purchase_order_item
--	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SUPPLIER] AS PS
--	  ON PPO.COD_SUPPLIER = PS.COD_SUPPLIER AND PS.COD_BOB_SUPPLIER IS NOT NULL AND PS.COD_SYSTEM = ''''OMS''''
--	  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS_CONTRACT_TYPE] AS PPOCT
--	  ON PPO.COD_PURCHASE_ORDER_CONTRACT_TYPE = PPOCT.COD_PURCHASE_ORDER_CONTRACT_TYPE  
--	  WHERE PPO.DAT_PURCHASE_ORDER > CAST(''''' + @CUT_OFF_DATE + ''''' AS DATE) 
--	  AND PDR.COD_TIMESTAMP > ' + @THRESHOLD + '	 
--	  GROUP BY  PDR.COD_DELIVERY_RECEIPT												
--			,PDR.COD_DATE
--			,PDR.COD_PURCHASE_ORDER
--			,PPO.COD_PO_NUMBER
--			,PS.COD_BOB_SUPPLIER
--			,PPO.COD_SUPPLIER
--			,PS.DSC_SUPPLIER_NAME_EN
--			,PPO.DSC_SUPPLIER_CONTACT_NAME
--			,PPOCT.DSC_CONTRAT_TYPE_NAME			
--			,PDR.COD_TIMESTAMP) DS_INT ) aux	
--		where aux.rn <= ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
--		''))  AS OMS_DATA');


SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT5 AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.id_delivery_receipt 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT ID_COMPANY
												 ,PPR.[No_] AS PO_OMS												 
												 ,PPR.[No_ of Items on PO Receipt] AS CountItems
												 ,PPR.[Purchase Receipt Amount Excl_ VAT] AS EXCL_VAT
												 ,PPR.[Purchase Receipt Amount Incl_ VAT] AS INCL_VAT 								  
					    FROM [dbo].[Posted Purchase Receipts] AS PPR										
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PO_OMS] = CAST(OMS_DATA.id_delivery_receipt as nvarchar)
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');


SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''PurchaseReceipt'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');
--vaiting for validation --SET @UPDATENAV = (char(13) + char(10) + 'UPDATE [AIG_Nav_Jumia_Reconciliation].[dbo].[OMS_RECONCILIATION_PO_RECEIPTS] 
--										  SET PR.Nav_Count_Items_Posted = NAV.[No_ of Items on PO Receipt],PR.Nav_Receipt_Amount_Excl_Vat = NAV.[Purchase Receipt Amount Excl_ VAT],
--                                        PR.Nav_Receipt_Amount_Incl_Vat = NAV.[Purchase Receipt Amount Incl_ VAT] 
--										  FROM [AIG_Nav_Jumia_Reconciliation].[dbo].[OMS_RECONCILIATION_PO_RECEIPTS] AS PR
--										  INNER JOIN 
--										  (select * from openquery([BI-DWH-NAV],''select [No_],
--                                        [No_ of Items on PO Receipt],
--                                          [Purchase Receipt Amount Excl_ VAT],
--                                          [Purchase Receipt Amount Incl_ VAT] from [dbo].[Posted Purchase Receipts] Where id_company = ''''' + @COUNTRY_CODE +  ''''' '') as NAV
--										  ON (PR.Nav_PO_Receipt=NAV.[No_])
--										  ')



     --select @QUERY_OMS,@QUERY_RABBIT,@QUERY_NAV--,@UPDATENAV
	  EXEC(@QUERY_OMS + @QUERY_RABBIT + @QUERY_NAV);
	  SET @ROWCOUNT = @@ROWCOUNT
	  IF @ROWCOUNT<@BATCH_COUNTER/4 BREAK;
	  
	  -- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT




END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

	CLOSE COUNTRIES_CURSOR
	DEALLOCATE COUNTRIES_CURSOR;

WITH CTE AS
(
SELECT [ID_COMPANY],[OMS_PO_Receipt_No],ROW_NUMBER() over(partition by id_company,[OMS_PO_Receipt_No] order by  OMS_PO_Receipt_Creation_Date desc) as rownum
FROM [AIG_Nav_Jumia_Reconciliation].[dbo].[OMS_RECONCILIATION_PO_RECEIPTS]
)
DELETE FROM CTE WHERE cte.rownum>1


GO
