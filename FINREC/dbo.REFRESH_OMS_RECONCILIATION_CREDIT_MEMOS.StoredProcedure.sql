USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_CREDIT_MEMOS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_CREDIT_MEMOS]
AS
-- drop table OMS_RECONCILIATION_CREDIT_MEMOS
DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_OMS_2 NVARCHAR(MAX);
DECLARE @QUERY_OMS_3 NVARCHAR(MAX);
DECLARE @QUERY_OMS_4 NVARCHAR(MAX);
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



--SET @PRINT_MSG = 'OMS_RECONCILIATION_CREDIT_MEMOS ==== PROCESSING RABBIT MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT3];

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
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_CREDIT_MEMOS';
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
			DECLARE @IN_SQL NVARCHAR(MAX);			
			SET @INSERT = 'INSERT INTO ' +  @TABLE_TO_CREATE;
			SET @INSERT_INTO='';	
			SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(OMS_Creation_Date),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
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
	  -- DROP TABLE OMS_RECONCILIATION_CREDIT_MEMOS
	  SET @BATCH_COUNTER = 100000;	

	  SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
'SELECT  
 OMS_DATA.ID_COMPANY AS ID_Company
,OMS_DATA.credit_note_number AS OMS_Credit_Memo_No
,OMS_DATA.created_at AS OMS_Creation_Date     
,OMS_DATA.package_number AS OMS_Package_No
,OMS_DATA.bob_id_customer AS OMS_Customer_No
,OMS_DATA.OMS_Count_Retail_Items
,OMS_DATA.OMS_Count_Marketplace_Items
,OMS_Sum_Retail_Revenue_Before_Discount_Excl_VAT
,OMS_Sum_Retail_Revenue_Before_Discount_Incl_VAT
,OMS_Sum_Retail_Cart_Rule_Discount_Excl_VAT               
,OMS_Sum_Retail_Cart_Rule_Discount_Incl_VAT
,OMS_Sum_Retail_Discount_Voucher_Excl_VAT
,OMS_Sum_Retail_Discount_Voucher_Incl_VAT
,OMS_Sum_Retail_Revenue_After_Discount_Excl_VAT
,OMS_Sum_Retail_Revenue_After_Discount_Incl_VAT
,OMS_Sum_Marketplace_Revenue_Before_Discount_Incl_VAT
,OMS_Sum_Marketplace_Cart_Rule_Discount_Excl_VAT
,OMS_Sum_Marketplace_Cart_Rule_Discount_Incl_VAT
,OMS_Sum_marketplace_Discount_Voucher_Excl_VAT
,OMS_Sum_marketplace_Discount_Voucher_Incl_VAT
,OMS_Sum_Marketplace_Revenue_After_Discount_Incl_VAT 
,(OMS_Sum_Marketplace_Revenue_Before_Discount_Incl_VAT - OMS_Sum_Marketplace_Revenue_After_Discount_Incl_VAT) AS OMS_Sum_Marketplace_Discount_Incl_VAT 
,OMS_Shipping_Fees
,OMS_Shipping_Fees_Retail
,OMS_Shipping_Fees_Marketplace
,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
,RABO_DATA.[id_message] AS OMS_Message_ID');
SET @QUERY_OMS_2 = (char(13) + char(10) + '		
,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' 
	  WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' 
	  WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' 
	  WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  
	  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' 
	  WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' 
  ELSE ''UNKNOWN'' END) AS RabbitMQ_Status
,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
,NAV_DATA.[Status] AS Nav_Message_Status
,NAV_DATA.[Error Message] AS Nav_Error_Message
,CASE WHEN NAV_DATA_OP.credit_note_number_nav is null then ''False'' else ''True'' END AS Nav_Credit_Memo_Posted
,NAV_DATA_OP.[Amount excl_ VAT] AS Nav_Credit_Memo_Excl_VAT
,NAV_DATA_OP.[Amount Incl_ VAT] AS Nav_Credit_Memo_Incl_VAT	
,YEAR(OMS_DATA.created_at) AS OMS_Creation_Year 
	  ' + @INSERT_INTO + '
from openquery([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],'' select   ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
											,cn.id_credit_note
											,cn.credit_note_number
											,cn.created_at 
											,p.package_number
											,so.bob_id_customer
');
SET @QUERY_OMS_3 = ( char(13) + char(10) + ',SUM(CASE WHEN soi.is_marketplace=0   THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
,SUM(CASE WHEN soi.is_marketplace=1  THEN 1 ELSE 0 END)  as OMS_Count_Marketplace_Items
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN (soi.unit_price - soi.cart_rule_discount) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Retail_Revenue_Before_Discount_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN soi.unit_price ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Retail_Revenue_Before_Discount_Incl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN (soi.cart_rule_discount/(1+soi.tax_percent/100)) ELSE 0 END) as decimal (13,2)) as OMS_Sum_Retail_Cart_Rule_Discount_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN soi.cart_rule_discount ELSE 0 END) as decimal(13,2)) as OMS_Sum_Retail_Cart_Rule_Discount_Incl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (CASE WHEN soi.is_marketplace=0  THEN (soi.coupon_money_value/(1+soi.tax_percent/100)) ELSE 0 END) ELSE 0 END) ELSE 0 END) as decimal (12,2)) AS OMS_Sum_Retail_Discount_Voucher_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =0  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN soi.coupon_money_value ELSE 0 END) ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Retail_Discount_Voucher_Incl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =0  THEN (soi.unit_price - soi.tax_amount - (soi.cart_rule_discount/(1+soi.tax_percent/100)) - (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value/(1+soi.tax_percent/100))  ELSE 0 END)) ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Retail_Revenue_After_Discount_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace=0  THEN (soi.unit_price - soi.cart_rule_discount-(CASE WHEN (CASE WHEN so.fk_voucher_type=3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value) ELSE 0 END))ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Retail_Revenue_After_Discount_Incl_VAT 
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.unit_price) ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Marketplace_Revenue_Before_Discount_Incl_VAT 
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.unit_price - soi.cart_rule_discount - (CASE WHEN (CASE WHEN so.fk_voucher_type=3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value)  ELSE 0 END)) ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Marketplace_Revenue_After_Discount_Incl_VAT	
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.cart_rule_discount/(1+soi.tax_percent/100)) ELSE 0 END) as decimal(13,2)) as OMS_Sum_Marketplace_Cart_Rule_Discount_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN soi.cart_rule_discount ELSE 0 END) as decimal(13,2)) as OMS_Sum_Marketplace_Cart_Rule_Discount_Incl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.unit_price) ELSE 0 END) - SUM(CASE WHEN soi.is_marketplace  THEN (soi.unit_price - soi.tax_amount - soi.cart_rule_discount - (CASE WHEN (CASE WHEN so.fk_voucher_type=3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value)  ELSE 0 END)) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Marketplace_Discount_Incl_VAT
,CAST(SUM(ifnull(soi.shipping_fee,0)) as decimal (13,2)) AS OMS_Shipping_Fees
,CAST(ifnull(SUM(CASE WHEN soi.is_marketplace =0  THEN ifnull(soi.shipping_fee,0) END),0) as decimal (13,2)) AS OMS_Shipping_Fees_Retail
,CAST(ifnull(SUM(CASE WHEN soi.is_marketplace =1  THEN ifnull(soi.shipping_fee,0) END),0) as decimal (13,2)) AS OMS_Shipping_Fees_Marketplace
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value/(1+soi.tax_percent/100)) ELSE 0 END)ELSE 0 END) as decimal (13,2)) AS OMS_Sum_marketplace_Discount_Voucher_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value) ELSE 0 END) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_marketplace_Discount_Voucher_Incl_VAT
,CAST(SUM(CASE WHEN (CASE WHEN so.fk_voucher_type <> 3 THEN 0 ELSE 1 END) = 0 THEN (soi.coupon_money_value/(1+soi.tax_percent/100)) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Store_Credit_Excl_VAT
,CAST(SUM(CASE WHEN (CASE WHEN so.fk_voucher_type<>3 THEN 0 ELSE 1 END) = 0 THEN soi.coupon_money_value ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Store_Credit_Inc_VAT');
SET @QUERY_OMS_4 = ( char(13) + char(10) + '
from ims_sales_order_item as soi
join (select fk_sales_order_item from ims_sales_order_item_status_history where fk_sales_order_item_status=55 or fk_sales_order_item_status=44) as soish
on soish.fk_sales_order_item=soi.id_sales_order_item
join oms_credit_note_item as cni
on cni.id_credit_note_item = soi.fk_credit_note_item 
JOIN oms_credit_note as cn
on cn.id_credit_note=cni.fk_credit_note
JOIN oms_package_item as pi
	on pi.fk_sales_order_item=soi.id_sales_order_item
JOIN oms_package as p 
on p.id_package=pi.fk_package
JOIN ims_sales_order as so
on so.id_sales_order=p.fk_sales_order 									   
WHERE cn.created_at >''''' + @THRESHOLD + '''''
and cn.created_at >''''' + @CUT_OFF_DATE2 + '''''
GROUP BY 
cn.id_credit_note
,cn.credit_note_number
,cn.created_at 
,p.package_number
,so.bob_id_customer
Order by cn.created_at asc
limit  '+ CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
'') AS oms_data
'
);




--FROM OPENQUERY([BI-DWH-JUMIA], ''SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
--''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
--,VPNCN.credit_note_number as credit_note_number_oms	
--,VPNCN.id_credit_note
--,NAV_PK.COD_TRACKING_NUMBER
--,PSO.COD_ORDER_NR
--,PSO.COD_CUSTOMER
--,PSO.COD_SALES_RULE
--,PN.created_at as COD_DATE
--');

--SET @QUERY_OMS_3 = ( char(13) + char(10) + ',SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN 1 ELSE 0 END) as OMS_Count_Marketplace_Items
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (PSOI.MTR_UNIT_PRICE - PSOI.MTR_UNIT_TAX_AMOUNT) ELSE 0 END) AS OMS_Sum_Retail_Revenue_Before_Discount_Excl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN PSOI.MTR_UNIT_PRICE ELSE 0 END) AS OMS_Sum_Retail_Revenue_Before_Discount_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (PSOI.MTR_CART_RULE_DISCOUNT/(1+PSOI.MTR_TAX_PERCENT/100)) ELSE 0 END) as OMS_Sum_Retail_Cart_Rule_Discount_Excl_VAT															
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN PSOI.MTR_CART_RULE_DISCOUNT ELSE 0 END) as OMS_Sum_Retail_Cart_Rule_Discount_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (PSOI.MTR_COUPON_MONEY_VALUE/(1+PSOI.MTR_TAX_PERCENT/100)) ELSE 0 END) ELSE 0 END) ELSE 0 END) AS OMS_Sum_Retail_Discount_Voucher_Excl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN PSOI.MTR_COUPON_MONEY_VALUE ELSE 0 END) ELSE 0 END) AS OMS_Sum_Retail_Discount_Voucher_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (PSOI.MTR_UNIT_PRICE - PSOI.MTR_UNIT_TAX_AMOUNT - (PSOI.MTR_CART_RULE_DISCOUNT/(1+PSOI.MTR_TAX_PERCENT/100)) - (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE/(1+PSOI.MTR_TAX_PERCENT/100))  ELSE 0 END)) ELSE 0 END) AS OMS_Sum_Retail_Revenue_After_Discount_Excl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN (PSOI.MTR_UNIT_PRICE - PSOI.MTR_CART_RULE_DISCOUNT-(CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE) ELSE 0 END))ELSE 0 END) AS OMS_Sum_Retail_Revenue_After_Discount_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (PSOI.MTR_UNIT_PRICE) ELSE 0 END) AS OMS_Sum_Marketplace_Revenue_Before_Discount_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (PSOI.MTR_UNIT_PRICE - PSOI.MTR_CART_RULE_DISCOUNT - (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE)  ELSE 0 END)) ELSE 0 END) AS OMS_Sum_Marketplace_Revenue_After_Discount_Incl_VAT	
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (PSOI.MTR_CART_RULE_DISCOUNT/(1+PSOI.MTR_TAX_PERCENT/100)) ELSE 0 END) as OMS_Sum_Marketplace_Cart_Rule_Discount_Excl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN PSOI.MTR_CART_RULE_DISCOUNT ELSE 0 END) as OMS_Sum_Marketplace_Cart_Rule_Discount_Incl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (PSOI.MTR_UNIT_PRICE) ELSE 0 END) - SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (PSOI.MTR_UNIT_PRICE - PSOI.MTR_UNIT_TAX_AMOUNT - PSOI.MTR_CART_RULE_DISCOUNT - (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE)  ELSE 0 END)) ELSE 0 END) AS OMS_Sum_Marketplace_Discount_Incl_VAT
--,SUM(ISNULL(FEES.MTR_SHIPPING_AMOUNT_INCL_TAX,0)) AS OMS_Shipping_Fees
--,ISNULL(SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =0 THEN ISNULL(FEES.MTR_SHIPPING_AMOUNT_INCL_TAX,0) END),0) as OMS_Shipping_Fees_Retail
--,ISNULL(SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN ISNULL(FEES.MTR_SHIPPING_AMOUNT_INCL_TAX,0) END),0) as OMS_Shipping_Fees_Marketplace
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE/(1+PSOI.MTR_TAX_PERCENT/100)) ELSE 0 END)ELSE 0 END) AS OMS_Sum_marketplace_Discount_Voucher_Excl_VAT
--,SUM(CASE WHEN PSOI.MTR_IS_MARKETPLACE =1 THEN (CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE =''''coupon'''' THEN 1 ELSE 0 END) = 1 THEN (PSOI.MTR_COUPON_MONEY_VALUE) ELSE 0 END) ELSE 0 END) AS OMS_Sum_marketplace_Discount_Voucher_Incl_VAT
--,SUM(CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE not like ''''coupon'''' THEN 0 ELSE 1 END) = 0 THEN (PSOI.MTR_COUPON_MONEY_VALUE/(1+PSOI.MTR_TAX_PERCENT/100)) ELSE 0 END) AS OMS_Sum_Store_Credit_Excl_VAT
--,SUM(CASE WHEN (CASE WHEN PSR.DSC_SALES_RULE_SET_TYPE not like ''''coupon'''' THEN 0 ELSE 1 END) = 0 THEN PSOI.MTR_COUPON_MONEY_VALUE ELSE 0 END) AS OMS_Sum_Store_Credit_Inc_VAT 
--,VPNCN.CREATED_AT as COD_TIMESTAMP
--');
--SET @QUERY_OMS_4 = ( char(13) + char(10) + '
--from  [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[V_PRE_NAV_CREDIT_NOTE_ITEM] as PN
--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[V_PRE_NAV_CREDIT_NOTE] AS VPNCN
--     ON VPNCN.id_credit_note = PN.fk_credit_note
--LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM] PSOI
--	ON PSOI.COD_SALES_ORDER_ITEM = PN.ID_SALES_ORDER_ITEM AND PSOI.COD_SYSTEM=''''OMS''''
--left JOIN (select * from (select COD_BOB_SALES_ORDER_ITEM,MTR_SHIPPING_AMOUNT_INCL_TAX,row_number() over(partition by COD_BOB_SALES_ORDER_ITEM order by SK_DATE DESC) as rownum from [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_DW].[dbo].[M03_F01_FCT_SALES_ORDER_ITEM_FINANCE]) as FIN where FIN.rownum=1  )AS FEES
--ON FEES.COD_BOB_SALES_ORDER_ITEM=PSOI.COD_bob_SALES_ORDER_ITEM   
  
--LEFT JOIN (select a.* from (
--  select * from (SELECT  PSOISH.COD_DATE,PSOISH.COD_SALES_ORDER_ITEM AS COD_SALES_ORDER_ITEM_OMS,pack.COD_PACKAGE,PSOISH.COD_ORDER_NR,
--   row_number() over(partition by PSOISH.COD_SALES_ORDER_ITEM_STATUS,PSOISH.COD_SALES_ORDER_ITEM order by PSOISH.COD_DATE desc) rank
--    FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM_STATUS_HISTORY] AS PSOISH
--    JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE_ITEM] prep ON PSOISH.COD_SALES_ORDER_ITEM = prep.[COD_SALES_ORDER_ITEM_OMS]
--join [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE] pack ON pack.COD_PACKAGE = prep.COD_PACKAGE AND pack.COD_SYSTEM = ''''OMS''''
--    WHERE PSOISH.COD_SALES_ORDER_ITEM_STATUS = 56 AND PSOISH.COD_SYSTEM = ''''OMS'''') a where rank = 1 ) AS a) AS PP  
--     ON  PP.COD_SALES_ORDER_ITEM_OMS=PN.ID_SALES_ORDER_ITEM
--  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_Order] AS PSO
--           ON PSO.COD_ORDER_NR = psoi.COD_ORDER_NR 
--  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].V_PRE_OMS_PACKAGE AS NAV_PK     
--     ON NAV_PK.COD_PACKAGE = VPNCN.fk_PACKAGE   
--  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_Sales_RULE] PSR
--              ON PSO.COD_SALES_RULE = PSR.COD_SALES_RULE_CODE AND PSR.COD_SYSTEM=''''OMS''''  
--WHERE  VPNCN.CREATED_AT > ''''' + @THRESHOLD + ''''' 
--AND VPNCN.CREATED_AT > ''''' + @CUT_OFF_DATE + '''''
--GROUP BY 
--VPNCN.id_credit_note
--,VPNCN.credit_note_number
--,PN.created_at
--,NAV_PK.COD_TRACKING_NUMBER				 
--,PSO.COD_ORDER_NR
--,PSO.COD_CUSTOMER
--,PSO.COD_SALES_RULE
--,VPNCN.CREATED_AT
--			'') AS OMS_DATA' );

		SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT3 AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.id_credit_note
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT
										   ID_COMPANY
										  ,PSCM.[No_] AS credit_note_number_nav
										  ,PSCM.[Amount excl_ VAT]
										  ,PSCM.[Amount incl_ VAT]
					    FROM [dbo].[Posted Sales Credit Memos] AS PSCM									
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[credit_note_number_nav] = OMS_DATA.credit_note_number	
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

	SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''SalesCreditMemo'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');	
	

	  select  CONCAT(@QUERY_OMS_1, @QUERY_OMS_2 , @QUERY_OMS_3,  @QUERY_OMS_4, @QUERY_RABBIT, @QUERY_NAV )
	  --EXEC (@QUERY_OMS_1+ @QUERY_OMS_2 + @QUERY_OMS_3 + @QUERY_OMS_4+ @QUERY_RABBIT + @QUERY_NAV );
	  SET @ROWCOUNT = @@ROWCOUNT
	  IF @ROWCOUNT<@BATCH_COUNTER/3 BREAK; /*BREAK WHILE 1=1 LOOP*/ 
	  -- PRINT LAST LOADED COUNT
		SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT

   END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;

GO
