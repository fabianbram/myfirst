USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_POS]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_POS]
AS

DECLARE @CUT_OFF_DATE2 NVARCHAR(50);
DECLARE @PRINT_MSG NVARCHAR(200);
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

SET @PRINT_MSG = 'OMS_RECONCILIATION_POS ==== PROCESSING RABBIT MESSAGES ==== ' 
RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
EXEC [dbo].[REFRESH_TMP_RAB_MESSAGES_ENT4];

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
SET @TABLE_TO_CREATE = 'OMS_RECONCILIATION_POS';
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

		SET @BATCH_COUNTER = 1000000;	  
		-- QUERY HERE
		SET @QUERY_OMS =(@INSERT +  char(13) + char(10) + 
		   ' SELECT  
		     OMS_DATA.ID_COMPANY
			,OMS_DATA.id_purchase_order AS N''OMS_PO_ID''
			,OMS_DATA.po_number AS ''OMS_PO_No''
			,OMS_DATA.contractname AS N''OMS_Contract_Type'' 
			,OMS_DATA.statusname AS ''PO_Status''
			,CAST(OMS_DATA.created_at as date) AS N''OMS_PO_CREATION_DATE''
			,CASE WHEN RABO_DATA.COD_TIMESTAMP IS NULL THEN ''False'' ELSE ''True'' END AS OMS_Message_Created  
			,RABO_DATA.[id_message] AS OMS_Message_ID	
			,(CASE WHEN RABO_DATA.fk_request_status = 1 THEN N''In Queue'' WHEN RABO_DATA.fk_request_status = 2 THEN N''Queue Failed'' WHEN RABO_DATA.fk_request_status = 3 THEN N''Request Ok'' WHEN RABO_DATA.fk_request_status = 4 THEN N''Request Failed''  WHEN RABO_DATA.fk_request_status = 5 THEN N''Invalid'' WHEN RABO_DATA.fk_request_status = 6 THEN N''Locked'' ELSE N''UNKNOWN'' END)AS RabbitMQ_Status
			,RABO_DATA.response_message AS N''RabbitMQ_Error_Message''
			,NAV_DATA.[Message ID] AS N''Message_ID''
			,NAV_DATA.[Status] as N''Nav_Message_Status''
			,NAV_DATA.[Error Message] as N''Nav_Error_Message''
			,CASE WHEN NAV_DATA_OP.[PO_NO] IS NULL THEN N''False'' ELSE N''True'' END AS N''NAV_PO_CREATED''
			,OMS_DATA.created_at as COD_TIMESTAMP
			,year(OMS_DATA.created_at) AS N''OMS_PO_CREATION_DATE_YEAR''					  
			' + @INSERT_INTO + '
			from openquery ([BI-OMS_LIVE_' + @SHORT_COUNTRY_CODE + '],''select ''''' + @COUNTRY_CODE + ''''' as Id_company 
																				,id_purchase_order
																				,po_number
																				,poct.name as contractname
																				,pos.name as statusname
																				,po.created_at 
																        FROM ims_purchase_order as po
																		left JOIN ims_purchase_order_contract_type as poct
																			on poct.id_purchase_order_contract_type = po.fk_purchase_order_contract_type
																		left JOIN ims_purchase_order_status as pos
																			on pos.id_purchase_order_status = po.fk_purchase_order_status
																		where po.created_at > ''''' + @CUT_OFF_DATE2 + '''''
																		and po.created_at > ''''' + @THRESHOLD + '''''
																		order by po.created_at asc
																		limit ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
														              ''
						    ) as oms_data'
						 );
						  
			--FROM( SELECT * FROM OPENQUERY([BI-DWH-JUMIA],''
			--							  select * from(SELECT DS_INT.*, row_number() over(order by DS_INT.COD_TIMESTAMP ASC) as rn
			--							  from (SELECT top ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + ' N''''' + @COUNTRY_CODE + ''''' as ID_COMPANY
			--							  ,COD_PURCHASE_ORDER										  
			--							  ,COD_PO_NUMBER										 
			--							  ,DAT_PURCHASE_ORDER
			--							  ,PO.COD_TIMESTAMP 
			--							  ,POS.DSC_NAME
			--							  ,POCT.DSC_CONTRAT_TYPE_NAME
			--							  FROM [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS] PO
			--							  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS_STATUS] POS
			--							  ON PO.COD_PURCHASE_ORDER_STATUS = POS.COD_PURCHASE_ORDER_STATUS 
			--							  LEFT JOIN [AIG_JUMIA_' + @SHORT_COUNTRY_CODE + '_STG].[dbo].[PRE_PURCHASE_ORDERS_CONTRACT_TYPE] AS POCT
			--							  ON PO.COD_PURCHASE_ORDER_CONTRACT_TYPE = POCT.COD_PURCHASE_ORDER_CONTRACT_TYPE
			--							  WHERE DAT_PURCHASE_ORDER > CAST(''''' + @CUT_OFF_DATE2 + ''''' AS DATE) 
			--							  AND PO.COD_TIMESTAMP > ' + @THRESHOLD + '
			--							  GROUP BY COD_PURCHASE_ORDER
			--									,COD_PO_NUMBER
			--									,DAT_PURCHASE_ORDER
			--									,PO.COD_TIMESTAMP
			--									,POS.DSC_NAME
			--									,POCT.DSC_CONTRAT_TYPE_NAME ) DS_INT ) aux	
			--								where aux.rn <= ' + CAST(@BATCH_COUNTER as NVARCHAR(50)) + '
			--								''))  AS OMS_DATA';

		SET @QUERY_RABBIT = (char(13) + char(10) + 'LEFT JOIN 
				   [dbo].[TMP_RAB_MESSAGES_ENT4] as RABO_DATA
				   ON RABO_DATA.id_related_entity = OMS_DATA.id_purchase_order
						AND RABO_DATA.ID_COMPANY =  OMS_DATA.ID_COMPANY	
						
				   LEFT JOIN 
				  (SELECT * FROM OPENQUERY([BI-DWH-NAV],
										''SELECT distinct ID_COMPANY,
												 PO.[PO No_] as PO_NO
																				  
					    FROM [dbo].[Purchase Orders] AS PO										
				        WHERE id_company = ''''' + @COUNTRY_CODE +  '''''											
						'')) AS NAV_DATA_OP
				  ON NAV_DATA_OP.[PO_NO] = OMS_DATA.po_number
						AND NAV_DATA_OP.[ID_COMPANY] = OMS_DATA.ID_COMPANY			
						 ');
		
			SET @QUERY_NAV =  (char(13) + char(10) + ' -- NAV DW
				  LEFT JOIN (select * from TMP_NAV_MESSAGES where ID_COMPANY = ''' + @COUNTRY_CODE +  ''' and [Message Type] = ''PurchaseOrder'') AS NAV_DATA 
				  ON NAV_DATA.[Message ID]  = RABO_DATA.[id_message] 
						AND NAV_DATA.[ID_COMPANY] = RABO_DATA.ID_COMPANY							
							');


	   --select @QUERY_OMS,@QUERY_RABBIT,@QUERY_NAV	
		EXEC(@QUERY_OMS+@QUERY_RABBIT+@QUERY_NAV)
		SET @ROWCOUNT = @@ROWCOUNT
		IF @ROWCOUNT<@BATCH_COUNTER/4 BREAK;
	  -- PRINT (@QUERY_NAV)
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
select 
	ID_COMPANY
	,OMS_PO_ID
	,COD_TIMESTAMP
	,row_number()over(partition by ID_COMPANY,OMS_PO_ID order by COD_Timestamp DESC) as ranku
  FROM [AIG_Nav_Jumia_Reconciliation].[dbo].[OMS_RECONCILIATION_POS]

)
DELETE FROM CTE WHERE ranku > 1






GO
