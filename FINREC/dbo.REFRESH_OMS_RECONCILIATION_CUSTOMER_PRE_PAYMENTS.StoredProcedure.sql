USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_PRE_PAYMENTS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_PRE_PAYMENTS]
AS
-- drop table OMS_RECONCILIATION_PRE_CUSTOMER_PRE_PAYMENTS
DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
DECLARE @QUERY_OMS_1 NVARCHAR(MAX);
DECLARE @QUERY_NAV NVARCHAR(MAX);
DECLARE @QUERY_RABBIT NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @INC_COL NVARCHAR(50);
DECLARE @REP_ALL bit;
DECLARE @TABLE_TO_CREATE NVARCHAR(250);
DECLARE @TABLE_TO_CREATE_SCHEMA NVARCHAR(250);
DECLARE @COUNTER INT;
DECLARE @BATCH_COUNTER INT;
DECLARE @ROWCOUNT INT;


SET @PRINT_MSG = 'OMS_RECONCILIATION_CUSTOMER_PRE_PAYMENTS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT20];

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
	WHERE ACTIVE = 1 ORDER BY [Order] asc;
-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_CUSTOMER_PRE_PAYMENTS';
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
		DECLARE @INSERT NVARCHAR(150);
		DECLARE @INSERT_INTO NVARCHAR(150);
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
	
			SET @BATCH_COUNTER = 1000000;	  	  
	  

			SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT 
				  OMS_DATA.ID_COMPANY as ID_Company
				  ,OMS_DATA.order_nr as OMS_Order_No 
				  ,OMS_DATA.updated_at AS OMS_Creation_Date
				  ,OMS_DATA.bob_id_customer AS OMS_Customer_No
				  ,OMS_DATA.payment_method AS OMS_Source_Provider
				  ,OMS_DATA.grand_total AS OMS_Pre_payment_Amount
				  ,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created  
				  ,RABO_DATA.id_message AS OMS_Message_ID
				  ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				  ,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
				  ,NAV_DATA.[Status] AS Nav_Message_Status
				  ,NAV_DATA.[Error Message] AS Nav_Error_Message
				  ,CASE WHEN NAV_DATA_OP.PCPP_NO is null then ''False'' else ''True'' END AS Nav_Customer_Pre_Payment_Posted
				  ,NAV_DATA_OP.Amount AS Nav_Amount_Posted
				  ,OMS_DATA.COD_TIMESTAMP
				  ,YEAR(OMS_DATA.COD_DATE) AS OMS_Creation_Year
				  ' + @INSERT_INTO + '
				  FROM OPENQUERY([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],'' select ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY 
																						,so.order_nr
																						,ifnull(so.updated_at,-1) as updated_at
																						,so.bob_id_customer
																						,so.payment_method
																						,so.grand_total
																				join ims_sales_order_item as soi
																				join ims_sales_order as so
																				on so.id_sales_order=soi.fk_sales_order
																				join ims_sales_order_process sop 
																				on so.fk_sales_order_process=sop.id_sales_order_process 
																				join ims_sales_order_history as soh
																				on soh.order_nr = so.order_nr
																				where sop.payment_type = ''Prepayment''
																				and fk_sales_order_status = 2
																				and r.created_at > ''''' + @THRESHOLD +'''''   
																				and r.created_at > ''''' + @CUT_OFF_DATE2 +''''' 
																				order by  r.created_at asc
																			'' 
								  ) AS OMS_DATA 
				  ');
			      --FROM OPENQUERY([BI-DWH-JUMIA],''SELECT DISTINCT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
									--				  ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
									--				  ,PSO.COD_DATE
									--				  ,PSO.COD_ORDER_NR
									--				  ,PSOI.COD_SALES_ORDER
									--				  ,PSO.COD_CUSTOMER
									--				  ,PSO.COD_PAYMENT_METHOD
									--				  ,PSO.COD_TIMESTAMP
									--				  ,PSO.MTR_TOTAL_AMOUNT_SALES_ORDER
									--			  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_ITEM] AS PSOI
									--			  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER] AS PSO
									--				  ON PSOI.COD_ORDER_NR = PSO.COD_ORDER_NR AND PSOI.COD_SYSTEM=''''OMS''''
									--			  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_OMS_SALES_ORDER_PROCESS] AS PSOP
									--				  ON PSO.COD_ORDER_NR = PSOP.order_nr
									--			  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_SALES_ORDER_STATUS_HISTORY] AS PSOSH
									--				  ON PSOSH.COD_ORDER_NR=PSO.COD_ORDER_NR and PSOSH.COD_SALES_ORDER_STATUS=2
									--			  WHERE PSO.COD_TIMESTAMP > ' + @THRESHOLD + '
									--			  AND PSO.COD_TIMESTAMP > ' + @CUT_OFF_DATE_BI + ' 											 
									--			  '') AS OMS_DATA' );

SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENT20] AS RABO_DATA 
				   ON RABO_DATA.id_related_entity = OMS_DATA.[COD_SALES_ORDER] 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT DISTINCT ID_COMPANY,
												 PCPP.[No_] as PCPP_NO
												 ,PCPP.[Amount] AS Amount	 								  
					    FROM [dbo].[Posted Customer Pre-Payments] AS PCPP							
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PCPP_NO] = OMS_DATA.[COD_ORDER_NR] 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''CustomerPrePayment'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');

        -- Select @QUERY_OMS_1,@QUERY_RABBIT,@QUERY_NAV
			EXEC(@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
		  -- PRINT LAST LOADED COUNT
		   SET @ROWCOUNT = @@ROWCOUNT	
		   IF @ROWCOUNT<@BATCH_COUNTER/4 BREAK; /*break while 1=1 loop*/

			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;



GO
