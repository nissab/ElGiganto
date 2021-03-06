-- CREATE OR ALTER PROCEDURE test
--     (@tal1 int,
--     @tal2 int,
--     @summainternal int output)
-- AS
-- SET @summainternal = @tal1 + @tal2
-- GO

-- DECLARE @sum int;
-- EXEC test 1,2, @summainternal = @sum output
-- SELECT @sum;
-- GO

-- select * from Warehouse

/* GetAllProducts */
CREATE OR ALTER VIEW GetAllProducts
AS
    SELECT p.Id, c.Name CategoryName, p.Name ProductName, Price, IsInStock, Popularity, w.InStock, w.Reserved, w.Available
    FROM Products p
        INNER JOIN Categories c
        ON p.CategoryId = c.Id
        INNER JOIN Warehouse w 
        ON w.ProductId = p.Id
GO


SELECT ProductName, Popularity
FROM GetAllProducts
GO
SELECT *
FROM GetAllProducts
GO


/* GetProductDetails & Popularity +1 */
CREATE OR ALTER PROCEDURE GetProductDetails
    (@ProcuctId int)
AS
SELECT c.Name Category, p.Name Product, Price, IsInStock, Popularity
FROM Products p
    INNER JOIN Categories c
    ON p.CategoryId = c.Id
WHERE p.Id = @ProcuctId
UPDATE Products 
	SET Products.Popularity +=1
	WHERE Products.Id = @ProcuctId
GO


/* ListProductsByCategory */
CREATE OR ALTER PROCEDURE ListProductsByCategory
    (@IsInStock int)
AS
SELECT c.Name AS CategoryName, p.Name ProductName, p.Price, p.Popularity
FROM Products p
    INNER JOIN Categories c ON p.CategoryId = c.Id

WHERE p.IsInStock = @IsInStock
    OR p.IsInStock = 1

GROUP BY c.Name, p.Name, p.Price, p.Popularity
ORDER BY c.Name, p.Popularity DESC
GO

EXEC ListProductsByCategory 1
GO

CREATE OR ALTER PROCEDURE CreateCustomer
    @CustomerNumber int
AS
BEGIN
    INSERT INTO Customers
        (CustomerNumber)
    VALUES
        (@CustomerNumber)
END
    GO
SELECT *
FROM Customers
GO


/* CreateCart & Return CartId */
CREATE OR ALTER PROCEDURE CreateCart
    @customerNumber int
AS
BEGIN
    INSERT INTO Carts
        (CustomerId)
    SELECT Customers.Id
    FROM Customers
    WHERE @customerNumber = Customers.CustomerNumber
    RETURN SCOPE_IDENTITY()
END
    GO

DECLARE @CartIdOut int;
EXEC @CartIdOut = CreateCart 123456
SELECT @CartIdOut AS CartId
SELECT *
FROM Customers
SELECT *
FROM Carts
GO



/* Delete carts older than 14 days */
CREATE OR ALTER PROCEDURE ClearOldCarts
AS
BEGIN
    DELETE FROM Carts
    WHERE (DATEDIFF(WEEK, DateTimeCreated, GETDATE())) >0
END
GO

EXEC ClearOldCarts
GO

SELECT *
FROM Carts;
GO


/* Insert into cart */
CREATE OR ALTER PROCEDURE InsertIntoCart
    (@CartId int,
    @ProductId int,
    @Amount int)
AS
BEGIN
    /* existing produkt */
    IF EXISTS
    (SELECT ProductId
    FROM Products_Cart pc
    WHERE pc.Id = @CartId AND pc.ProductId = @ProductId)
    
    UPDATE Products_Cart
    SET Products_Cart.Amount += @Amount
    WHERE Products_Cart.Id = @CartId AND Products_Cart.ProductId = @ProductId

    ELSE
    /* new product */
    INSERT INTO Products_Cart
        (CartId, ProductId, Amount)
    VALUES
        (@CartId, @ProductId, @Amount)
END
    GO

SELECT *
FROM Products_Cart GO

EXEC InsertIntoCart  1, 6, 15
GO

SELECT Name, Popularity
FROM Products

SELECT *
FROM Products_Cart
WHERE CartId = 1
GO

SELECT *
FROM Products_Cart
SELECT *
FROM Products_Order
GO

/* GetCart */
CREATE OR ALTER PROCEDURE GetCart
    (@CartId int)
AS
BEGIN
    SELECT p.Name, pc.Amount, p.Price, pc.Sum
    FROM Products_Cart pc
        INNER JOIN Products p ON pc.ProductId = p.Id
    WHERE pc.CartId = @CartId;
END
    GO

EXEC GetCart 1


SELECT *
FROM Customers
GO

/* CheckoutCart */
CREATE OR ALTER PROCEDURE CheckoutCart
    (@CustomerNumber int,
    @CartId int)
AS
BEGIN
    -- create order and insert customer id
    DECLARE @OrderId int

    INSERT INTO Orders
        (CustomerId)
    SELECT Customers.Id
    FROM Customers
    WHERE @CustomerNumber = Customers.CustomerNumber
    SET @OrderId = SCOPE_IDENTITY()

    -- update customer details
    UPDATE Orders
    SET 
        Orders.CustomerName = c.CustomerName,
        Orders.CustomerStreet = c.CustomerStreet,
        Orders.CustomerZip = c.CustomerZip,
        Orders.CustomerCity = c.CustomerCity
    FROM Orders o
        INNER JOIN Customers c ON o.CustomerId = c.Id
    WHERE o.CustomerId = c.Id

    -- move products from cart
    INSERT INTO Products_Order
        (OrderId, ProductId, Amount)
    SELECT @OrderId, Products_Cart.ProductId, Products_Cart.Amount
    FROM Products_Cart
    WHERE Products_Cart.CartId = @CartId

    -- reserve products in warehouse
    UPDATE Warehouse
    SET Warehouse.Reserved = po.Amount
    FROM Products_Order po
    WHERE Warehouse.ProductId = po.ProductId
        AND po.OrderId = @OrderId


    -- empty cart
    DELETE FROM Products_Cart
    WHERE Products_Cart.CartId = @CartId

    --generate random order number
    SELECT FLOOR(RAND()*(99999999-10000000+1))+10000000 AS OrderNumber
END
    GO


/* Popularitetsrapport */
CREATE OR ALTER PROCEDURE CheckPopularity
    (@CategoryId int)
AS
SELECT TOP 5
    CategoryId, Name, Popularity
FROM Products
WHERE CategoryId = @CategoryId
ORDER BY Popularity DESC
GO

EXEC CheckPopularity 1
GO

/* ShipOrder */
CREATE OR ALTER PROCEDURE ShipOrder
    (@OrderId int)
AS
BEGIN
    -- log stock transaction
    INSERT INTO StockTransactions
        (OrderId, ProductId, StockChange, DateTimeOfTransaction, TransactionId)
    SELECT po.OrderId, po.ProductId, po.Amount * (-1), GETDATE(), 1
    FROM Products_Order po
    WHERE po.OrderId = @OrderId

    -- ta bort reservationen
    UPDATE Warehouse
    SET Warehouse.Reserved += StockTransactions.StockChange,
    Warehouse.InStock += StockTransactions.StockChange
    FROM Warehouse INNER JOIN StockTransactions
        ON Warehouse.ProductId = StockTransactions.ProductId
    WHERE Warehouse.ProductId = StockTransactions.ProductId
        AND StockTransactions.OrderId = @OrderId
END
GO
SELECT *
FROM Warehouse
GO
UPDATE Warehouse SET Reserved = 0 WHERE id = 15
GO

/* StockAdjustment */
CREATE OR ALTER PROCEDURE StockAdjustment
    (@ProductId int,
    @StockChange int,
    @TransactionId int = NULL
)
AS
BEGIN
    -- log stock transaction
    INSERT INTO StockTransactions
        (ProductId, StockChange, DateTimeOfTransaction, TransactionId)
    VALUES(@ProductId, @StockChange, GETDATE(), @TransactionId)

    -- justera lagersaldo
    UPDATE Warehouse
    SET Warehouse.InStock += @StockChange
    WHERE Warehouse.ProductId = @ProductId
END
GO
EXEC StockAdjustment 1, 13
GO
SELECT *
FROM Warehouse
SELECT *
FROM StockTransactions
GO

/* ReturnOrder */
CREATE OR ALTER PROCEDURE ReturnOrder
    (@OrderId int,
    @ProductId int,
    @AmountReturned int,
    @StockChange int = NULL
)
AS
BEGIN
    -- log stock transaction
    INSERT INTO StockTransactions
        (OrderId, ProductId, StockChange, DateTimeOfTransaction, TransactionId, AmountReturned)
    VALUES(@OrderId, @ProductId, @StockChange, GETDATE(), 3, @AmountReturned)

    IF @StockChange IS NOT NULL
        -- justera lagersaldo
        UPDATE Warehouse
        SET Warehouse.InStock += @StockChange
        WHERE Warehouse.ProductId = @ProductId
END
GO
EXEC ReturnOrder 19, 14, 10,10
SELECT *
FROM StockTransactions
GO

/* ListAllOrdersTotalAmount */
CREATE OR ALTER PROCEDURE ListAllOrdersTotalAmount
AS
BEGIN
    SELECT Products_Order.OrderId,
        sum(Products_Order.Amount * Products.Price) AS OrderTotal
    FROM Products_Order
        INNER JOIN Products ON Products.Id = Products_Order.ProductId
    WHERE Products_Order.ProductId = Products.Id
    GROUP BY OrderId
    ORDER BY OrderTotal DESC
END
GO

EXEC ListAllOrdersTotalAmount
GO

/* CTE variant */
WITH
    TotalPerOrder (OrderId, OrderTotal)
    AS
    (
        SELECT Products_Order.OrderId,
            sum(Products_Order.Amount * Products.Price) AS OrderTotal
        FROM Products_Order
            INNER JOIN Products ON Products.Id = Products_Order.ProductId
        WHERE Products_Order.ProductId = Products.Id
        GROUP BY OrderId
    )
SELECT TotalPerOrder.*
FROM TotalPerOrder
ORDER BY OrderTotal DESC
GO


/* GetTotalAmountOfOrder */
CREATE OR ALTER PROCEDURE GetTotalAmountOfOrder
    (@OrderId int)
AS
BEGIN
    SELECT Products_Order.OrderId,
        sum(Products_Order.Amount * Products.Price) AS OrderTotal
    FROM Products_Order
        INNER JOIN Products ON Products.Id = Products_Order.ProductId
    WHERE Products_Order.ProductId = Products.Id
        AND Products_Order.OrderId = @OrderId
    GROUP BY OrderId
END
GO

EXEC GetTotalAmountOfOrder 15
GO



/* TopPopularProducts */
CREATE OR ALTER VIEW MostPopular
AS
    WITH
        TopPopularProducts (CategoryName, ProductName, Popularity)
        AS
        (
            SELECT Categories.Name, Products.Name, Products.Popularity
            FROM Products
                INNER JOIN Categories ON Categories.Id = Products.CategoryId
            WHERE Products.CategoryId = Categories.Id
        )
    SELECT TopPopularProducts.*,
        ROW_Number() OVER (PARTITION BY CategoryName ORDER BY Popularity DESC) AS Ranking
    FROM TopPopularProducts
    GROUP BY CategoryName, ProductName, Popularity
GO

SELECT *
FROM MostPopular

SELECT CategoryName, ProductName, Popularity, Ranking
FROM MostPopular
WHERE Ranking <= 5
GO


/* TopReturnedProducts */
CREATE OR ALTER VIEW TopReturnedProducts
AS
    WITH
        TopReturned(Name, AmountReturned)
        AS
        (
            SELECT Products.Name, sum(StockTransactions.AmountReturned) AS AmountReturned
            FROM Products
                INNER JOIN StockTransactions ON Stocktransactions.ProductId = Products.Id
            GROUP BY Products.Name
        )
    SELECT TopReturned.*,
        ROW_Number() OVER (ORDER BY AmountReturned DESC) AS Ranking
    FROM TopReturned
    GROUP BY Name, AmountReturned
GO

SELECT TOP 5
    *
FROM TopReturnedProducts
GO
/* Kategorirapport */

-- (en rad per kategori)
--  Sålt antal innevarande månad
--  Sålt antal föregående månad
--  Sålt antal senaste 365 dagarna
--  Returnerat antal innevarande månad
--  Returnerat antal föregående månad
--  Returnerat antal senaste 365 dagar


CREATE OR ALTER VIEW Sold_This_Month
AS
    (
    SELECT c.Name AS Category, SUM(st.StockChange * -1) AS Sold_This_Month
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE MONTH(st.DateTimeOfTransaction) = MONTH(GETDATE())
        AND st.transactionid = 1
    GROUP BY c.Name
    )
GO

CREATE OR ALTER VIEW Sold_Last_Month
AS
    (
    SELECT c.Name AS Category, SUM(st.StockChange * -1) AS Sold_Last_Month
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE MONTH(st.DateTimeOfTransaction) = MONTH(GETDATE()) -1
        AND st.transactionid = 1
    GROUP BY c.Name
    )
GO

CREATE OR ALTER VIEW Sold_Last_365_Days
AS
    (
    SELECT c.Name AS Category, SUM(st.StockChange * -1) AS Sold_Last_365
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE st.DateTimeOfTransaction > (GETDATE() - 365)
        AND st.transactionid = 1
    GROUP BY c.Name
)
GO


CREATE OR ALTER VIEW Returned_This_Month
AS
    (
    SELECT c.Name AS Category, SUM(st.AmountReturned) AS Returned_This_Month
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE MONTH(st.DateTimeOfTransaction) = MONTH(GETDATE())
        AND st.transactionid = 3
    GROUP BY c.Name
    )
GO

CREATE OR ALTER VIEW Returned_Last_Month
AS
    (
    SELECT c.Name AS Category, SUM(st.AmountReturned) AS Returned_Last_Month
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE MONTH(st.DateTimeOfTransaction) = MONTH(GETDATE()) -1
        AND st.transactionid = 3
    GROUP BY c.Name
    )
GO

CREATE OR ALTER VIEW Returned_Last_365_Days
AS
    (
    SELECT c.Name AS Category, SUM(st.AmountReturned) AS Returned_Last_365_Days
    FROM Stocktransactions st
        INNER JOIN Products p ON p.Id = st.ProductId
        INNER JOIN Categories c ON c.Id = p.CategoryId
    WHERE st.DateTimeOfTransaction > (GETDATE() - 365)
        AND st.transactionid = 3
    GROUP BY c.Name
)
GO



SELECT * from Kategorirapport

GO
SELECT *
FROM returned_This_Month

SELECT *
FROM returned_last_Month

SELECT *
FROM Returned_Last_365_Days

SELECT *
FROM Sold_This_Month

SELECT *
FROM Sold_Last_Month

SELECT *
FROM Sold_Last_365_Days


SELECT *
FROM StockTransactions
SELECT *
FROM Categories