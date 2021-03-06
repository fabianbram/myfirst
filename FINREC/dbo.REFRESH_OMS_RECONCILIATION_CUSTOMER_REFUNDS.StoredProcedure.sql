USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_REFUNDS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_REFUNDS]
AS

DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(150);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_NAV NVARCHAR(MAX);
DECLARE @QUERY_RABBIT NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @TABLE_TO_CREATE NVARCHAR(250);
DECLARE @TABLE_TO_CREATE_SCHEMA NVARCHAR(250);
DECLARE @BATCH_COUNTER INT;
DECLARE @ROWCOUNT INT;

--SET @PRINT_MSG = 'OMS_RECONCILIATION_CUSTOMER_REFUNDS ==== PROCESSING RABBIT MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT21];

--SET @PRINT_MSG = '==== PROCESSING NAVISION MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_NAV_MESSAGES];

-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR FOR 
	SELECT ID_COMPANY
		, ID_COMPANY_SHORT
		, COUNTRY
		, CUT_OFF_DATE2
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1 ORDER BY [Order] asc;
-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_CUSTOMER_REFUNDS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2
		
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		

		DECLARE @INSERT NVARCHAR(150);
		DECLARE @INSERT_INTO NVARCHAR(150);
		DECLARE @MAXDATE NVARCHAR(100);

		SET @PRINT_MSG = 'PROCESSING COUNTRY: ' + @COUNTRY_CODE
		RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
				
			
		WHILE 1=1
		BEGIN
			  
			  IF OBJECT_ID('AIG_Nav_Jumia_Reconciliation.dbo.OMS_RECONCILIATION_CUSTOMER_REFUNDS') is not null
			  BEGIN
				  DECLARE @SQLSTRING as NVARCHAR(1000)
				  SET @SQLSTRING = N'SELECT @EDATE=isnull(MAX(OMS_Creation_Date),''1900-01-01'') FROM '+@TABLE_TO_CREATE+' WHERE ID_COMPANY = '''+@COUNTRY_CODE+''';'
				  SET @MAXDATE = N'@EDATE varchar (400) OUTPUT'
				  EXEC sp_executesql @SQLSTRING,@MAXDATE, @EDATE = @MAXDATE OUTPUT;	
				  	  SET @INSERT = 'INSERT INTO ' +  @TABLE_TO_CREATE;	
				  SET @INSERT_INTO=' ' ;	
				  -- get date for current country
			
			  END
			  ELSE
			  BEGIN	
				  SET @MAXDATE = '1900-01-01';	
				  SET @INSERT = '';
				  SET @INSERT_INTO='INTO ' +  @TABLE_TO_CREATE;			
			  END
			
			SET @BATCH_COUNTER = 1000000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT 
				   OMS_DATA.ID_COMPANY as id_company
				  ,OMS_DATA.refundNo as OMS_Refund_No 
				  ,OMS_DATA.created_at AS OMS_Creation_Date
				  ,OMS_DATA.order_nr AS OMS_Order_No
				  ,OMS_DATA.bob_id_customer AS OMS_Customer_No
				  ,OMS_DATA.name AS OMS_Source_Provider
				  ,OMS_DATA.Refund_Amount AS OMS_Refund_Amount
				  ,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created  
				  ,RABO_DATA.id_message AS OMS_Message_ID
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,RABO_DATA.response_message AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] AS Nav_Message_Status
				  ,NAV_DATA.[Error Message] AS Nav_Error_Message
				  ,CASE WHEN NAV_DATA_OP.PCPP_NO is null then ''False'' else ''True'' END AS Nav_Customer_Refund_Posted
				  ,NAV_DATA_OP.Amount AS Nav_Amount_Posted
				  ,YEAR(OMS_DATA.created_at) AS OMS_Creation_Year
				  ' + @INSERT_INTO + '
				  from openquery ([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],''select '''''+ @COUNTRY_CODE + ''''' as Id_company 
												 ,concat(so.order_nr,min(soi.id_sales_order_item)) as refundNo
										         ,sum(Cast(ifnull(soi.refunded_money,0)+ ifnull(soi.refunded_wallet_credit,0) + ifnull(soi.refunded_other,0)  + ifnull(soi.refunded_voucher,0)as decimal(13,2))) as Refund_amount
												 ,soi.fk_sales_order
												 ,soi.fk_refund_sales_order_process
												 ,sop.name
												 ,so.order_nr
												 ,soish.created_at
												 ,so.bob_id_customer
												 ,so.id_sales_order
											FROM ims_sales_order_item as soi
											JOIN ims_sales_order_item_status_history as soish 
												on soi.id_sales_order_item =soish.fk_sales_order_item and soish.fk_sales_order_item_status=56 
											JOIN ims_sales_order as so 
												on so.id_sales_order=soi.fk_sales_order
											JOIN ims_sales_order_process as sop
												on sop.id_sales_order_process = soi.fk_refund_sales_order_process
										   where soish.created_at > ''''' + @MAXDATE + '''''
										   and soish.created_at > ''''' + @CUT_OFF_DATE2 + '''''	
										   group by '''''+ @COUNTRY_CODE + '''''
													,soi.fk_sales_order
													,sop.name
													,so.order_nr
										            ,day(soish.created_at)
													,so.bob_id_customer
												   ,so.id_sales_order
											order by day(soish.created_at) ASC
									       limit ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
						                  '') AS OMS_DATA ')
		
		
			  --    FROM OPENQUERY([BI-DWH-JUMIA], ''SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
					--	''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
					--    ,PSOI.COD_SALES_ORDER_ITEM
					--	,PORO.RefundAmount
					--	,PORO.return_order_number
					--	,PSOSH.COD_DATE
					--	,PSO.COD_CUSTOMER
					--	,PSO.COD_SALES_ORDER_ID
					--	,Poro.name
					--	,PSO.COD_TIMESTAMP
					--	,PSO.COD_ORDER_NR
					--FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM] AS PSOI
					--LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_OMS_RETURN_ORDER] AS PORO
					-- ON PSOI.COD_SALES_ORDER_ITEM = PORO.fk_sales_order_item
					--JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER] AS PSO
					-- ON PSOI.COD_ORDER_NR = PSO.COD_ORDER_NR
					-- JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM_STATUS_HISTORY] AS PSOSH
					--ON PSOI.COD_SALES_ORDER_ITEM =PSOSH.COD_SALES_ORDER_ITEM AND PSOSH.COD_SYSTEM=''''OMS'''' AND PSOI.COD_SYSTEM=''''OMS'''' AND PSOSH.COD_SALES_ORDER_ITEM_STATUS=56
					--WHERE PSO.COD_TIMESTAMP > ' + @THRESHOLD + ' AND PSO.COD_TIMESTAMP > ' + @CUT_OFF_DATE + '										 
					--'') AS OMS_DATA' );

SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENT21] AS RABO_DATA 
				   ON RABO_DATA.id_related_entity = cast(OMS_DATA.id_sales_order as nvarchar)
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY
												 ,PCPP.[No_] as PCPP_NO
												 ,PCPP.Amount 								  
					    FROM [dbo].[Posted Customer Refunds] AS PCPP							
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PCPP_NO] = OMS_DATA.refundNo 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''CustomerRefund'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

     --select @QUERY_OMS_1,@QUERY_RABBIT,@QUERY_NAV
		EXEC(@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
		   SET @ROWCOUNT = @@ROWCOUNT

		IF 	@ROWCOUNT< @BATCH_COUNTER/3 BREAK /*BREAK WHILE1=1 LOOP*/

			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;



GO
