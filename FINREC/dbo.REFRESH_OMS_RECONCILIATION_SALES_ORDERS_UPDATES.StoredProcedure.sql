USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[REFRESH_OMS_RECONCILIATION_SALES_ORDERS_UPDATES]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[REFRESH_OMS_RECONCILIATION_SALES_ORDERS_UPDATES]
AS
-- drop table OMS_RECONCILIATION_SALES_ORDERS

DECLARE @QUERY_UPDATE NVARCHAR(MAX);
DECLARE @QUERY_UPDATE_2 NVARCHAR(MAX);
DECLARE @QUERY_UPDATE_3 NVARCHAR(MAX);
DECLARE @COUNTRY NVARCHAR(150);
DECLARE @COUNTRY_CODE NVARCHAR(50);
DECLARE @SHORT_COUNTRY_CODE NVARCHAR(50);
DECLARE @ROWCOUNT INT
DECLARE @PRINT_MSG NVARCHAR(200)



-- get all countries from config table
DECLARE COUNTRIES_CURSOR CURSOR LOCAL FOR 
	SELECT ID_COMPANY
	FROM OMS_RECONCILIATION_CONFIG 
	WHERE ACTIVE = 1
	ORDER BY [ORDER] ASC;

-- start process for each country
OPEN COUNTRIES_CURSOR
	-- get current country
	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE	
	WHILE @@FETCH_STATUS = 0	
	BEGIN	
	       SET @PRINT_MSG = 'Processing:'+@COUNTRY_CODE+'' 
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT				
		  
		   SET @QUERY_UPDATE =  (char(13) + char(10) + '---UPDATE NAV MESSAGES---
	
		   UPDATE SO
		   SET SO.Nav_Message_Status=MSG.[Status]
		   ,SO.Nav_Error_Message=MSG.[Error Message]
		   FROM [dbo].[OMS_RECONCILIATION_SALES_ORDERS] AS SO
		   JOIN [dbo].[TMP_NAV_MESSAGES] AS MSG 
		   ON SO.OMS_Message_ID=MSG.[Message ID] 
		   WHERE MSG.ID_COMPANY = ''' + @COUNTRY_CODE +  '''
		   ');
		   EXEC(@QUERY_UPDATE);
			SET @ROWCOUNT = @@ROWCOUNT
			
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'NAV Messages Updated: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT

		    SET @QUERY_UPDATE_2 =  (char(13) + char(10) + '
		   ---UPDATE NAV RECORDS----
		   UPDATE SO
		   SET SO.Nav_Sales_Order_Created=(CASE WHEN NAV.[No_] is null then ''False'' else ''True'' END)
		   FROM [dbo].[OMS_RECONCILIATION_SALES_ORDERS] AS SO
		   JOIN (SELECT [No_] FROM OPENQUERY([BI-DWH-NAV],''SELECT [No_] FROM [dbo].[Sales Orders] WHERE id_company = ''''' + @COUNTRY_CODE +  ''''' '')) AS NAV
		   ON NAV.[No_]=SO.OMS_SO_No');

		   EXEC(@QUERY_UPDATE_2);
			SET @ROWCOUNT = @@ROWCOUNT
			
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'NAV Records Updated: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT

		   SET @QUERY_UPDATE_3 =  (char(13) + char(10) +' 
		   ----UPDATE RABBIT MESSAGES ----
		   UPDATE SO
		   SET SO.OMS_Message_ID=ent.id_message
		   ,SO.RabbitMQ_Status=(CASE WHEN ent.fk_request_status = 1 THEN ''In Queue'' WHEN ent.fk_request_status = 2 THEN ''Queue Failed'' WHEN ent.fk_request_status = 3 THEN ''Request Ok'' WHEN ent.fk_request_status = 4 THEN ''Request Failed''  WHEN ent.fk_request_status = 5 THEN ''Invalid'' WHEN ent.fk_request_status = 6 THEN ''Locked'' ELSE ''UNKNOWN'' END)
		   ,SO.RabbitMQ_Error_Message=ent.response_message
		   FROM [dbo].[OMS_RECONCILIATION_SALES_ORDERS] AS SO
		   JOIN [dbo].[TMP_RAB_MESSAGES_ENT9]as ent 
		   ON SO.OMS_SO_No=ent.id_related_entity 
		   WHERE ent.id_company = ''' + @COUNTRY_CODE +  '''
		   ');
		   EXEC(@QUERY_UPDATE_3);
			SET @ROWCOUNT = @@ROWCOUNT
			-- PRINT LAST LOADED COUNT
			SET @PRINT_MSG = 'Rabbit Messages Updated: ' + CAST(@ROWCOUNT AS VARCHAR(150))
			RAISERROR(@PRINT_MSG,0,1) WITH NOWAIT
	     


	FETCH NEXT FROM COUNTRIES_CURSOR INTO @COUNTRY_CODE;
END

CLOSE COUNTRIES_CURSOR
DEALLOCATE COUNTRIES_CURSOR;




GO
