-- File: calculate_active_users.sql

-- Declare variables
DECLARE @currentDate DATE,
        @startOfMonth DATE,
        @dailyActiveUsers INT,
        @monthlyActiveUsers INT,
        @errorStatus INT,
        @errorSeverity INT,
        @errorState INT,
        @errorMessage VARCHAR(4000)

-- Initialize currentDate to today's date
SELECT @currentDate = CAST(GETDATE() AS DATE)

-- Initialize startOfMonth to the first day of the current month
SELECT @startOfMonth = DATEADD(MONTH, DATEDIFF(MONTH, 0, @currentDate), 0)

-- Begin transaction
BEGIN TRANSACTION

BEGIN TRY
    -- Calculate Daily Active Users
    SELECT @dailyActiveUsers = COUNT(DISTINCT user_id)
    FROM user_activity
    WHERE activity_date = @currentDate

    -- Print Daily Active Users
    PRINT 'Daily Active Users: ' + CAST(@dailyActiveUsers AS VARCHAR)

    -- Calculate Monthly Active Users
    SELECT @monthlyActiveUsers = COUNT(DISTINCT user_id)
    FROM user_activity
    WHERE activity_date >= @startOfMonth AND activity_date < DATEADD(MONTH, 1, @startOfMonth)

    -- Print Monthly Active Users
    PRINT 'Monthly Active Users: ' + CAST(@monthlyActiveUsers AS VARCHAR)

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
