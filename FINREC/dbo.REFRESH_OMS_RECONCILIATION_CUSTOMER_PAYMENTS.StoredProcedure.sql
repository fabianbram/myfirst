USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_PAYMENTS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_CUSTOMER_PAYMENTS]
AS
-- drop table OMS_RECONCILIATION_CUSTOMER_PAYMENTS
DECLARE @CUT_OFF_DATE2 NVARCHAR(100)
, @PRINT_MSG NVARCHAR(400)
, @QUERY_OMS_1 NVARCHAR(MAX)
, @QUERY_NAV NVARCHAR(MAX)
, @QUERY_RABBIT NVARCHAR(MAX)
, @COUNTRY NVARCHAR(150)
, @COUNTRY_CODE NVARCHAR(50)
, @SHORT_COUNTRY_CODE NVARCHAR(50)
, @INC_COL NVARCHAR(50)
, @REP_ALL bit
, @TABLE_TO_CREATE NVARCHAR(150)
, @TABLE_TO_CREATE_SCHEMA NVARCHAR(150)
, @COUNTER INT
, @BATCH_COUNTER INT
, @ROWCOUNT INT


--SET @PRINT_MSG = 'OMS_RECONCILIATION_CUSTOMER_PAYMENTS ==== PROCESSING RABBIT MESSAGES ==== ' 
--RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
--EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT8];

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
	WHERE ACTIVE = 1 ORDER BY [Order] asc;

-- reconciliation table to create
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_CUSTOMER_PAYMENTS';
SET @TABLE_TO_CREATE_SCHEMA = 'AIG_Nav_Jumia_Reconciliation'

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
		
	SET @COUNTER = 1;
	-- while you have countries to process
	WHILE @@FETCH_STATUS = 0
	BEGIN
		
		DECLARE @MAX_DATE NVARCHAR(100);
		DECLARE @INSERT NVARCHAR(100);
		DECLARE @INSERT_INTO NVARCHAR(100);
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
				  SET @IN_SQL = N'SELECT @EXTRACT_THRESHOLD=ISNULL(MAX(updated_at),''1900-01-01'') FROM ' + @TABLE_TO_CREATE + ' WHERE ID_COMPANY='''+ @COUNTRY_CODE  + ''';'			
				  SET @THRESHOLD = N'@EXTRACT_THRESHOLD varchar(100) OUTPUT';			
				  -- get date for current country
				  EXEC sp_executesql @IN_SQL,@THRESHOLD,@EXTRACT_THRESHOLD=@THRESHOLD OUTPUT;	
			  END
			  ELSE
			  BEGIN	
			        SET @INSERT = '' 
			        SET @INSERT_INTO = ' INTO ' +  @TABLE_TO_CREATE;
				  SET @THRESHOLD = '1900-01-01';	
		
					
			  END
			-- DROP TABLE OMS_RECONCILIATION_CUSTOMER_PAYMENTS
			SET @BATCH_COUNTER = 500000;	  	  
	  

SET @QUERY_OMS_1 = (@INSERT +  char(13) + char(10) + 
				  'SELECT
				   OMS_DATA.ID_COMPANY as ID_Company
				   ,OMS_DATA.id_reconciliation AS Oms_Payment_Reconciliation_No
				   ,OMS_DATA.package_number as Oms_Package_No
				   ,OMS_DATA.amount_received as OMS_Reconciled_Amount
				   ,OMS_DATA.OMS_Source_Provider
				   ,OMS_DATA.created_at AS OMS_Reconciliation_Date
				   ,OMS_DATA.payment_date AS OMS_Payment_Date
				   ,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created 
				   ,RABO_DATA.id_message AS OMS_Message_ID		
				   ,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN ''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN ''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN ''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN ''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN ''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)AS RabbitMQ_Status
				   ,CASE WHEN RABO_DATA.response_message='''' THEN ''NULL'' ELSE RABO_DATA.response_message END AS RabbitMQ_Error_Message
				   ,NAV_DATA.[Status] AS Nav_Message_Status
				   ,NAV_DATA.[Error Message] AS Nav_Error_Message
				   ,CASE WHEN NAV_DATA_OP.PCP_NO is null then ''False'' else ''True'' END AS Nav_Customer_Payment_Posted
				   ,NAV_DATA_OP.[Document Date] as Nav_Customer_Payment_Document_Date
				   ,NAV_DATA_OP.[Posting Date] as Nav_Customer_Payment_Posting_Date
				   ,OMS_DATA.updated_at 
				   ,YEAR(OMS_DATA.created_at) AS OMS_Reconciliation_Year
				   ' +  @INSERT_INTO + '
				   FROM OPENQUERY ([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],'' select ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY 
															 ,r.id_reconciliation
															 ,p.package_number
															 ,r.amount_received
															 ,r.method
															 ,case when r.created_at like ''''%00-00-00%'''' then ''''1900-01-01 00:00:00'''' else r.created_at end as created_at
															 ,ifnull(r.payment_date,''''1900-01-01'''') as payment_date
															 ,so.payment_method
															 ,sp.shipment_provider_name
															 ,CASE WHEN (so.payment_method=r.method or r.method='''' '''') THEN sp.shipment_provider_name ELSE r.method END as OMS_Source_Provider
															 ,ifnull(psh.updated_at,''''1900-01-01'''') as updated_at
														from oms_reconciliation as r
														join oms_package p 
														on r.id_reconciliation=p.fk_reconciliation
													    join (select  max(updated_at) as updated_at, fk_package from oms_package_status_history group by fk_package) as psh -- FETCH THE LAST UPDATED DATE FROM THE STATUS HISTORY OF PACKAGE FOR DELIVERED DATE
														on psh.fk_package = p.id_package
														join ims_sales_order as so
														on so.id_sales_order=p.fk_sales_order
														join ims_sales_order_process sop 
														on so.fk_sales_order_process=sop.id_sales_order_process 
														left join oms_package_dispatching pd 
														on pd.fk_package = p.id_package
														left join oms_shipment_provider sp 
														on sp.id_shipment_provider = pd.fk_shipment_provider
														where fk_status = 1 and payment_type != ''''Prepayment''''
														and psh.updated_at > CAST(''''' + @THRESHOLD  +''''' as datetime) 
														and psh.updated_at > CAST(''''' + @CUT_OFF_DATE2  +''''' as datetime)
														Order by updated_at asc
														limit ' +CAST(@BATCH_COUNTER as nvarchar)+'  
													'' 
								  ) AS OMS_DATA 
				   ');



				  --FROM OPENQUERY([BI-DWH-JUMIA], ''SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' 
						--				 ''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
						--				 ,PNOMR.id_reconciliation
						--				 ,PNOMR.package_number AS COD_PACKAGE
						--				 ,PNOMR.amount_received
						--				 ,PNOMR.method
						--				 ,PNOMR.created_at 
						--				 ,PNOMR.payment_date
						--				 ,PP.COD_TIMESTAMP
						--				 ,PNOMR.payment_method
						--				 ,PNOMR.shipment_provider_name
						--				  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_NAV_OMS_RECONCILIATION] AS PNOMR 
						--				  JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PACKAGE] AS PP 
						--						ON PP.COD_PACKAGE = PNOMR.id_package  AND PP.COD_SYSTEM = ''''OMS''''						
						--				  WHERE PNOMR.created_at  > ''''' + cast(@THRESHOLD as nvarchar) + ''''' 
						--					AND PNOMR.created_at  > ''''' + cast(@CUT_OFF_DATE as nvarchar) + ''''' 
						--				  Order by PNOMR.created_at  ASC
						--				          ''
						--		 ) AS OMS_DATA' );



SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [TMP_RAB_MESSAGES_ENT8] AS RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.[id_reconciliation] 
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT distinct ID_COMPANY
												 ,PCP.[No_] as PCP_NO 
												 ,PCP.[Document Date]
												 ,PCP.[Posting Date]
										   FROM [dbo].[Posted Customer Payments] AS PCP							
										   WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
				                        '')
				  ) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PCP_NO] = cast(OMS_DATA.[id_reconciliation] as nvarchar) 
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');

SET @QUERY_NAV =  (char(13) + char(10) + ' LEFT JOIN 
				  (SELECT * 
				   FROM TMP_NAV_MESSAGES 
				   WHERE ID_COMPANY = ''' + @COUNTRY_CODE +  ''' 
				   AND [Message Type] = ''PaymentReconcile''
				   ) AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');
	  

		--select (@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
	 EXEC(@QUERY_OMS_1+@QUERY_RABBIT+@QUERY_NAV);
			SET @ROWCOUNT = @@ROWCOUNT
			if @ROWCOUNT < @BATCH_COUNTER/4 break;
            --PRINT(@QUERY_NAV)
			SET @PRINT_MSG = 'Just loaded: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
    END

	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE,@SHORT_COUNTRY_CODE,@COUNTRY,@CUT_OFF_DATE2,@INC_COL,@REP_ALL
	END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;





GO
