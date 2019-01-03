 
use master 
-- This will show the performance improvements 
SET NOCOUNT ON

--create database named ColumnStoreDB


--Connect to your database 
 
use ColumnStoreDB
-- Create New Table based on [WideWorldImporters].[Warehouse].[StockItemTransactions]
--you can download WideWorldImporters from our google drive 
 
Select Top 0 * into [dbo].[StockItemTransactions] 
from [WideWorldImporters].[Warehouse].[StockItemTransactions]

--populate the table about 5 times from 
--[WideWorldImporters].[Warehouse].[StockItemTransactions]
 
Insert into [dbo].[StockItemTransactions]  Select top 5 * 
from [WideWorldImporters].[Warehouse].[StockItemTransactions]

 --copy the table into another one named 
 select  * into [dbo].[StockItemTransactionsNew]  from [dbo].[StockItemTransactions] 
 
-- Create clustered index on the first one table 
create clustered INDEX [ix_StockItemTransactionID_StockItemTransactions] 
ON [dbo].[StockItemTransactions] (StockItemTransactionID)

 --create clustered columnstore index on the second one table 
create clustered COLUMNSTORE INDEX [ix_StockItemTransactionID_StockItemTransactionsNew] 
ON [dbo].[StockItemTransactionsNew] 

--e.g.
CREATE CLUSTERED COLUMNSTORE INDEX  ....
 

--Lets Compare the results Normal VS  ColumnStore Index
--Open statistics IO and TIME 
 --e.g. set statistics io on
 set statistics io on
 set statistics time on

 --Select [StockItemTransactions] with regular Column Index
 --Select [StockItemTransactionsNew] with Columnstore Index
 
SELECT invoiceid, SUM(quantity) SumUnitPrice, AVG(quantity) AvgUnitPrice,
SUM(customerid) SumOrderQty, AVG(customerid) AvgOrderQty
FROM [dbo].[StockItemTransactions]
GROUP BY invoiceid

--Table 'StockItemTransactions'. 
--Scan count 1, 
--logical reads 2, 
--physical reads 0, 
--read-ahead reads 0, 
--lob logical reads 0, 
--lob physical reads 0, 
--lob read-ahead reads 0.

-- SQL Server Execution Times:
--   CPU time = 0 ms,  elapsed time = 7 ms.


SELECT invoiceid, SUM(quantity) SumUnitPrice, AVG(quantity) AvgUnitPrice,
SUM(customerid) SumOrderQty, AVG(customerid) AvgOrderQty
FROM [dbo].[StockItemTransactionsNew]
GROUP BY invoiceid

--Table 'StockItemTransactionsNew'. 
--Scan count 1, 
--logical reads 0, 
--physical reads 0, 
--read-ahead reads 0, 
--lob logical reads 14, 
--lob physical reads 0, 
--lob read-ahead reads 0.

--SQL Server Execution Times:
--CPU time = 0 ms,  elapsed time = 69 ms.

--OPen Excution plan and check the Execution Mode in both different queries.
--without: sort=78%, clustered index scan=22%
--with: no sort, hash match=36% columnstore index scan=64%

--Lets Play with some System table 

--from sys.partitions and sys.tables 
--select table_name, rows number (rows) , data_compression_desc 

	SELECT 
    t.NAME AS TableName,
    p.rows AS RowCounts,
	data_compression_desc
FROM 
    sys.tables t
INNER JOIN 
    sys.partitions p ON t.OBJECT_ID = p.OBJECT_ID 
WHERE 
    t.NAME like 'StockItemTransactions%' 
ORDER BY 
    t.Name

--using column_store_segments &  column_store_row_groups 
--show table size
SELECT index_type_desc, page_count,
 record_count, avg_page_space_used_in_percent 
 FROM sys.dm_db_index_physical_stats
    (DB_ID(N'columnStoreDB'), OBJECT_ID(N'dbo.StockItemTransactions',N'U'), NULL, NULL , 'DETAILED'); 
EXEC dbo.sp_spaceused @objname = N'dbo.StockItemTransactions', @updateusage = true;

SELECT index_type_desc, page_count,
 record_count, avg_page_space_used_in_percent 
 FROM sys.dm_db_index_physical_stats
    (DB_ID(N'columnStoreDB'), OBJECT_ID(N'dbo.StockItemTransactionsNew',N'U'), NULL, NULL , 'DETAILED'); 
EXEC dbo.sp_spaceused @objname = N'dbo.StockItemTransactionsNew', @updateusage = true;

--answer the next questions 
--1. How many segments are for each column ? 1 segement for each column
--2. Which Row group is the biggest ? they are all the same (880 bytes)
SELECT i.name, p.object_id, p.index_id, i.type_desc, s.column_id, rg.size_in_bytes, 
    COUNT(*) AS number_of_segments  
FROM sys.column_store_segments AS s   
INNER JOIN sys.partitions AS p   
    ON s.hobt_id = p.hobt_id   
INNER JOIN sys.indexes AS i   
    ON p.object_id = i.object_id  
INNER JOIN sys.column_store_row_groups AS rg
    ON i.object_id = rg.object_id
GROUP BY rg.size_in_bytes, i.name, p.object_id, p.index_id, i.type_desc, s.column_id ; 


--for each column in out table 
--select the column name , data-type, count of segmentation , totl rows , size  on disk 

SELECT COL_NAME (p.object_id , s.column_id ) as columnName, t.name as DataType, 
COUNT(*) AS number_of_segments,SUM(s.row_count) as numberOfRows,
rg.size_in_bytes as SizeOnDisk   
FROM sys.column_store_segments AS s   
INNER JOIN sys.partitions AS p   
    ON s.hobt_id = p.hobt_id   
INNER JOIN sys.indexes AS i   
    ON p.object_id = i.object_id  
INNER JOIN sys.column_store_row_groups AS rg
    ON i.object_id = rg.object_id
INNER JOIN sys.columns AS c
    ON c.object_id = i.object_id and c.column_id = s.column_id
INNER JOIN sys.types AS t
    ON t.user_type_id = c.user_type_id 
where OBJECT_NAME(rg.object_id) = 'StockItemTransactionsNew'
GROUP BY t.name, rg.size_in_bytes,  p.object_id, s.column_id, rg.object_id; 

-- Show the space savings again
-- Query to find all the ColumnStore Indexes in a given database
SELECT i.name, Object_name(p.object_id) [TableName], p.index_id, i.type_desc, 
    COUNT(*) AS number_of_segments
FROM sys.column_store_segments AS s 
INNER JOIN sys.partitions AS p 
    ON s.hobt_id = p.hobt_id 
INNER JOIN sys.indexes AS i 
    ON p.object_id = i.object_id
GROUP BY i.name, p.object_id, p.index_id, i.type_desc ;
GO

--open Database Standard report to see both tables's size on disk.
 

