USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_SALES_DELIVERIES]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_SALES_DELIVERIES]
AS
-- drop table OMS_RECONCILIATION_SALES_DELIVERIES
DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_OMS_2 NVARCHAR(MAX);
DECLARE @QUERY_OMS_3 NVARCHAR(MAX);
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


--PRINT 'Deleting Rows';
--DELETE FROM OMS_RECONCILIATION_SALES_DELIVERIES; -- Deleting the table because the records on the source do not have historic changes
--Print Cast(@@ROWCOUNT as varchar) + ' rows deleted' ;	

--SET @PRINT_MSG = 'OMS_RECONCILIATION_SALES_DELIVERIES ==== PROCESSING RABBIT MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT11];

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
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_SALES_DELIVERIES';
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
				  SET @INSERT_INTO = ''
			
				  SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(OMS_Delivery_Date),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
				  SET @THRESHOLD = N'@EXTRACT_THRESHOLD varchar(100) OUTPUT';			
				  -- get date for current country
				  EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
			  END
			  ELSE
			  BEGIN
				  SET @THRESHOLD = '1900-01-01'		
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END
		
			SET @BATCH_COUNTER = 800000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT DISTINCT OMS_DATA.ID_Company
,OMS_DATA.package_number AS OMS_Package_No
,OMS_DATA.updated_at AS OMS_Delivery_Date
,OMS_DATA.order_nr AS OMS_SO_No
,OMS_DATA.bob_id_customer AS OMS_Customer_No				  
,SUM(CASE WHEN soi.is_marketplace=0   THEN 1 ELSE 0 END) as OMS_Count_Retail_Items
,SUM(CASE WHEN soi.is_marketplace=1  THEN 1 ELSE 0 END)  as OMS_Count_Marketplace_Items
,CAST(SUM(CASE WHEN soi.is_marketplace=0 THEN (soi.unit_price - soi.cart_rule_discount) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Retail_Revenue_Before_Discount_Excl_VAT
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
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.unit_price) ELSE 0 END) as decimal(13,2)) - CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (soi.unit_price - soi.cart_rule_discount - (CASE WHEN (CASE WHEN so.fk_voucher_type=3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value)  ELSE 0 END)) ELSE 0 END) as decimal(13,2)) AS OMS_Sum_Marketplace_Discount_Incl_VAT
			    ');
 SET @QUERY_OMS_2 = (char(13) + char(10) + ',CAST(SUM(ifnull(soi.shipping_fee,0)) as decimal (13,2)) AS OMS_Shipping_Fees
,CAST(ifnull(SUM(CASE WHEN soi.is_marketplace =0  THEN ifnull(soi.shipping_fee,0) END),0) as decimal (13,2)) AS OMS_Shipping_Fees_Retail
,CAST(ifnull(SUM(CASE WHEN soi.is_marketplace =1  THEN ifnull(soi.shipping_fee,0) END),0) as decimal (13,2)) AS OMS_Shipping_Fees_Marketplace
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value/(1+soi.tax_percent/100)) ELSE 0 END)ELSE 0 END) as decimal (13,2)) AS OMS_Sum_marketplace_Discount_Voucher_Excl_VAT
,CAST(SUM(CASE WHEN soi.is_marketplace =1  THEN (CASE WHEN (CASE WHEN so.fk_voucher_type = 3 THEN 1 ELSE 0 END) = 1 THEN (soi.coupon_money_value) ELSE 0 END) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_marketplace_Discount_Voucher_Incl_VAT
,CAST(SUM(CASE WHEN (CASE WHEN so.fk_voucher_type <> 3 THEN 0 ELSE 1 END) = 0 THEN (soi.coupon_money_value/(1+soi.tax_percent/100)) ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Store_Credit_Excl_VAT
,CAST(SUM(CASE WHEN (CASE WHEN so.fk_voucher_type<>3 THEN 0 ELSE 1 END) = 0 THEN soi.coupon_money_value ELSE 0 END) as decimal (13,2)) AS OMS_Sum_Store_Credit_Inc_VAT 
,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created
,RABO_DATA.id_message AS OMS_Message_ID	
,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
,NAV_DATA.[Status] AS Nav_Message_Status
,NAV_DATA.[Error Message] AS Nav_Error_Message
,CASE WHEN NAV_DATA_OP.SO_NO is null then ''False'' else ''True'' END AS Nav_Sales_Invoice_Posted
,NAV_DATA_OP.[Amount excl_ VAT] AS Nav_Sales_Invoice_Amount_Excl_VAT
,NAV_DATA_OP.[Amount Incl_ VAT] AS Nav_Sales_Invoice_Amount_Incl_VAT
,YEAR(OMS_DATA.updated_at) AS OMS_Delivery_Year  
' +  @INSERT_INTO + ' 
 FROM OPENQUERY([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '], ''select	''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
,p.package_number
,psh.updated_at
,so.order_nr
,so.bob_id_customer
,soi.is_marketplace
,soi.unit_price
,soi.cart_rule_discount 
,soi.tax_percent
,so.fk_voucher_type
,soi.coupon_money_value
,soi.shipping_fee
');

SET @QUERY_OMS_3 = '
FROM ims_sales_order_item as soi
JOIN oms_package_item as pi
	on pi.fk_sales_order_item=soi.id_sales_order_item
JOIN ims_sales_order_item_status_history as soish
	on soi.id_sales_order_item=soish.fk_sales_order_item and soish.fk_sales_order_item_status=27
JOIN oms_package as p 
	on p.id_package=pi.fk_package
JOIN (select  max(updated_at) as updated_at, fk_package from oms_package_status_history group by fk_package) as psh -- FETCH THE LAST UPDATED DATE FROM THE STATUS HISTORY OF PACKAGE FOR DELIVERED DATE
	on psh.fk_package = p.id_package
JOIN ims_sales_order as so
on so.id_sales_order=p.fk_sales_order 
WHERE psh.updated_at > ''''' + @CUT_OFF_DATE2+ '''''
and psh.updated_at > ''''' + @THRESHOLD+ '''''
GROUP BY	p.package_number
,psh.updated_at
,so.order_nr
,so.bob_id_customer
ORDER BY  psh.updated_at ASC
LIMIT ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
''
) AS OMS_DATA ';	

SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   TMP_RAB_MESSAGES_ENT11 AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.package_number
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY
												 ,SO.[No_] as SO_NO												
												 ,SO.[Amount excl_ VAT]
												 ,SO.[Amount Incl_ VAT]
												  									  
					    FROM [dbo].[Posted Sales Invoices] AS SO									
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

	  

			--EXEC(@QUERY_OMS_1+ @QUERY_OMS_2+@QUERY_OMS_3 + @QUERY_RABBIT + @QUERY_NAV);
			SELECT @QUERY_OMS_1,@QUERY_OMS_2,@QUERY_OMS_3,@QUERY_RABBIT,@QUERY_NAV
			
			SET @ROWCOUNT = @@ROWCOUNT
			IF @ROWCOUNT < 200 BREAK;
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;





GO
