USE [AIG_Nav_Jumia_Reconciliation]
GO
/****** Object:  StoredProcedure [dbo].[SchemaInfoDW]    Script Date: 2/26/2016 5:41:19 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[SchemaInfoDW]
@linkedserver nvarchar(100),
@SHORT_COUNTRY NVARCHAR(100),
@filter1 nvarchar(MAX),
@table nvarchar(100),
@filter2 nvarchar(MAX)

AS

if(@table ='')
	  BEGIN
	  if(@linkedserver = 'JUMIA')
			begin
			DECLARE @openqueryj as nvarchar(600)=
			'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT TABLE_CATALOG,TABLE_NAME FROM [AIG_JUMIA_'+@SHORT_COUNTRY+'_DW].INFORMATION_SCHEMA.TABLES ORDER BY TABLE_NAME'')'
		   EXEC(@openqueryj)
			end
	  ELSE
			BEGIN
			DECLARE @openqueryn as nvarchar(600)=
			'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT TABLE_CATALOG,TABLE_NAME FROM [AIG_NAV_DW].INFORMATION_SCHEMA.TABLES ORDER BY TABLE_NAME'')'
		   EXEC(@openqueryn)
			END
	  END
if(@table <> '' )
	  BEGIN
			if(@linkedserver = 'JUMIA')
				  BEGIN
				  DECLARE @openquery2 as nvarchar(600)= char(13) + char(10) +
				  'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE FROM [AIG_JUMIA_'+@SHORT_COUNTRY+'_DW].INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME= '''''+ @table+ ''''''')'
				  EXEC(@openquery2)
				  DECLARE @openquerya as nvarchar(600)= char(13) + char(10) +
				  'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT '+@filter1+'  FROM [AIG_JUMIA_'+@SHORT_COUNTRY+'_DW].dbo.'+@table+' '+@filter2+' '')'
				  EXEC(@openquerya)
				  END
			ELSE
				  BEGIN
				  DECLARE @openquery3 as nvarchar(600)= char(13) + char(10) +
				  'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT TABLE_NAME,COLUMN_NAME,DATA_TYPE FROM [AIG_NAV_DW].INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME= '''''+ @table+ ''''''')'
				  EXEC(@openquery3)
				  DECLARE @openqueryc as nvarchar(600)= char(13) + char(10) +
				  'SELECT * FROM OPENQUERY([BI-DWH-'+@linkedserver+'],''SELECT '+@filter1+'  FROM [AIG_NAV_DW].dbo.['+@table+'] '+@filter2+' '')'
				  EXEC(@openqueryc)
				  END
			END




GO
