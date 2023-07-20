-- File: update_price.sql

-- Declare variables
DECLARE @productId INT,
        @productName VARCHAR(255),
        @productCost DECIMAL(10,2),
        @productMarkupPercent DECIMAL(5,2),
        @calculatedPrice DECIMAL(10,2),
        @errorStatus INT,
        @errorSeverity INT,
        @errorState INT,
        @errorMessage VARCHAR(4000)

-- Create a temporary table to hold products data
IF OBJECT_ID('tempdb..#products') IS NOT NULL
    DROP TABLE #products

CREATE TABLE #products (
    product_id INT,
    product_name VARCHAR(255),
    product_cost DECIMAL(10,2),
    product_markup_percent DECIMAL(5,2),
    product_price DECIMAL(10,2)
)

-- Insert a new product into the temporary products table
INSERT INTO #products (product_id, product_name, product_cost, product_markup_percent, product_price)
VALUES (1, 'Test Product', 100.00, 20.00, 0.00)

-- Initialize a cursor to fetch each product from the temporary table
DECLARE product_cursor CURSOR FOR 
SELECT product_id, product_name, product_cost, product_markup_percent
FROM #products

-- Open the cursor
OPEN product_cursor

-- Perform the first fetch and store the values in variables
FETCH NEXT FROM product_cursor 
INTO @productId, @productName, @productCost, @productMarkupPercent

-- Check @@FETCH_STATUS to see if there are any more rows to fetch
WHILE @@FETCH_STATUS = 0
BEGIN
    -- Begin transaction
    BEGIN TRANSACTION

    BEGIN TRY
        -- Calculate the price
        SET @calculatedPrice = @productCost + (@productCost * @productMarkupPercent / 100.0)

        -- Print the calculated price
        PRINT 'Product ID: ' + CAST(@productId AS VARCHAR) + ', Product Name: ' + @productName + ', Calculated Price: ' + CAST(@calculatedPrice AS VARCHAR)

        -- Update the product price in the temporary table
        UPDATE #products
        SET product_price = @calculatedPrice
        WHERE product_id = @productId

        -- If we reach here, it means no error has occurred, so we can commit the transaction
        COMMIT TRANSACTION
    END TRY
    BEGIN CATCH
        -- Get error details
        SELECT 
        @errorStatus = ERROR_NUMBER(),
        @errorSeverity = ERROR_SEVERITY(),
        @errorState = ERROR_STATE(),
        @errorMessage = ERROR_MESSAGE()

        -- Rollback transaction in case of error
        ROLLBACK TRANSACTION

        -- Print the error details
        PRINT 'Error Number: ' + CAST(@errorStatus AS VARCHAR) 
        PRINT 'Error Severity: ' + CAST(@errorSeverity AS VARCHAR)
        PRINT 'Error State: ' + CAST(@errorState AS VARCHAR)
        PRINT 'Error Message: ' + @errorMessage
    END CATCH

    -- Fetch the next product
    FETCH NEXT FROM product_cursor 
    INTO @productId, @productName, @productCost, @productMarkupPercent
END 

-- Close the cursor
CLOSE product_cursor
DEALLOCATE product_cursor

-- Delete the updated product from the temporary table
DELETE FROM #products
WHERE product_id = 1

-- Drop the temporary table
DROP TABLE #products
