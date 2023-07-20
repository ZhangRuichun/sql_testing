USE [FPS]
GO

/****** Object:  StoredProcedure [dbo].[DT_KalibratePriceChange]    Script Date: 03/07/2019 17:02:51 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DT_KalibratePriceChange]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[DT_KalibratePriceChange]
GO

USE [FPS]
GO

/****** Object:  StoredProcedure [dbo].[DT_KalibratePriceChange]    Script Date: 03/07/2019 17:02:51 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

/*** 7/14/2021 - Fix the end digit by change datatype to Money of table MUSADTSQL1.DTMUSAKalibrate.dbo.ProposedPrices ***/

CREATE PROCEDURE [dbo].[DT_KalibratePriceChange] AS

--Create a Table Varible to hold prices and price information.

DECLARE @PriceChanges TABLE (
	Store INT NOT NULL,
	EffectiveDate DATETIME  NULL,
	FuelType TINYINT NOT NULL, 
	Price SMALLINT NOT NULL,
    GiftCardPrice SMALLINT NULL
)
DECLARE @MonthDay	INT
DECLARE @Today		DATETIME

DECLARE @FPSPriceChanges as TABLE (
	Store			INT NOT NULL,
	UpdateStatus	CHAR(1) NULL,
	Effective		DATETIME NOT NULL,
	NewEffective	DATETIME,
	Regular			SMALLINT NULL,
	RegularGC		SMALLINT NULL,
	RegularPumpOnly BIT NOT NULL,
	RegularOverride BIT NOT NULL,
	Plus			SMALLINT NULL,
	PlusGC			SMALLINT NULL,
	PlusPumpOnly	BIT NOT NULL,
	PlusOverride	BIT NOT NULL,
	Premium			SMALLINT NULL,
	PremiumGC		SMALLINT NULL,
	PremiumPumpOnly BIT NOT NULL,
	PremiumOverride BIT NOT NULL,
	Diesel			SMALLINT NULL,
	DieselGC		SMALLINT NULL,
	DieselPumpOnly	BIT NOT NULL,
	DieselOverride	BIT NOT NULL,
	Approved		BIT NOT NULL,
	Violation		TINYINT NULL
)
DECLARE @PMS AS TABLE (
	Store			INT NOT NULL,
	RegularPrice	MONEY NULL
)

DECLARE @PriceStrategies AS TABLE (
	Store			INT,
	Strategy		INT,
	MoveTo			MONEY,
	MoveAmount		INT,
	CompAverage		MONEY,
	CompHi			MONEY,		
	CompLo			MONEY,	
	CompOver		INT,
	Margin			FLOAT
)

DECLARE @COUNTER	INT
DECLARE @ADDRESS	VARCHAR(100)
DECLARE @BODY		VARCHAR(5000)
DECLARE @XML		VARCHAR(5000)

SET @Today = GETDATE()
SET @MonthDay = DAY(@Today)

-- Get the unprocessed price changes from the Data Transfer server
-- They have to be converted from text to actual numbers, etc. 

/*CHG0049090: adding the view so we can exclude QuickChek sites from being in this process*/

INSERT INTO @PriceChanges
SELECT
	CAST(SiteId AS INT),
    EffectiveDate,
    CAST(ProductCode AS INT),
    CAST(CASE IncreasePrice WHEN 0 THEN PriceValue * 1000 ELSE ((PriceValue + 0.01) * 1000 ) END AS SMALLINT), -- PriceValue already changed to Money from its orig table
	0
FROM
	MUSADTSQL1.DTMUSAKalibrate.dbo.ProposedPrices
JOIN [RetailOrg].dbo.[SI_StoreInfo] 
		ON [SI_StoreInfo].[StoreNumber] = CAST([ProposedPrices].[SiteId] AS int)
JOIN [RetailOrg].[dbo].[RetailChain] RetailChain
		ON [SI_StoreInfo].[RetailChainID] = [RetailChain].[RetailChainID]
WHERE
    IsProcessed = 0
	AND RetailChain.ChainName NOT LIKE '%Q%'

--Calculate the giftcard price.
UPDATE @PriceChanges SET 
	--GiftCardPrice = Price - (GiftCard * 1000)
	GiftCardPrice = PriceChanges.Price - CurrentFuelPriceDetails.DiscountAmount
FROM
		@PriceChanges PriceChanges
	--INNER JOIN dbo.Stores_FuelVitals FuelVitals ON PriceChanges.Store = FuelVitals.StoreNumber
	INNER JOIN dbo.CurrentFuelPriceDetails CurrentFuelPriceDetails ON CurrentFuelPriceDetails.Store = PriceChanges.Store
			
--Since all prices are sent to a store in a price change file
--and only price might be sent from Kalibrate, the prices not
--being sent from Kalibrate need to be included in the prices
--to be sent to the store.  Which means they need to be added
--here, so they will be inserted into the price queue, and so
--that they will be sent to the store portal, and so that the
--trigger will eventually update the CurrentFuelPriceDetails.
INSERT INTO @PriceChanges (
	Store,	EffectiveDate,		FuelType,		Price,		GiftCardPrice
)
SELECT
	Details.Store,
	NULL AS EffectiveDate,
    Details.FuelType,
    Details.Price,
    Details.ShoppingCardPrice
FROM
		@PriceChanges PriceChanges
	INNER JOIN
		dbo.CurrentFuelPriceDetails Details
			ON Details.Store = PriceChanges.Store
WHERE
	NOT EXISTS (SELECT PriceChanges.Store FROM @PriceChanges PriceChanges 
		WHERE PriceChanges.Store = Details.Store 
			AND PriceChanges.FuelType = Details.FuelType)

--Products other than Regular, Plus, Premium, and Diesel, can
--not be handled by the regular FPS process.  Which means the
--CurrentFuelPriceDetails table should have the prices of any
--of the other products such as E15, E85, Kerosene, or any E0
--fuels must be updated now.  It is okay that the 'FPS fuels'
--are being updated now too, because the trigger on the table
--named CurrentPrices, will eventually, make the same update.
UPDATE dbo.CurrentFuelPriceDetails SET
    Price = PriceChanges.Price,
    ShoppingCardPrice = PriceChanges.GiftCardPrice,
    NewPrice = PriceChanges.Price,
    NewShoppingCardPrice = PriceChanges.GiftCardPrice,
    CurrentPrice = PriceChanges.Price,
    CurrentShoppingCardPrice = PriceChanges.GiftCardPrice
FROM 
		dbo.CurrentFuelPriceDetails
	INNER JOIN
		@PriceChanges PriceChanges
			ON PriceChanges.Store = CurrentFuelPriceDetails.Store
			 AND PriceChanges.FuelType = CurrentFuelPriceDetails.FuelType

	

-- ___                     _     ___       _          ____       _             ___                        
--|_ _|_ __  ___  ___ _ __| |_  |_ _|_ __ | |_ ___   |  _ \ _ __(_) ___ ___   / _ \ _   _  ___ _   _  ___ 
-- | || '_ \/ __|/ _ \ '__| __|  | || '_ \| __/ _ \  | |_) | '__| |/ __/ _ \ | | | | | | |/ _ \ | | |/ _ \
-- | || | | \__ \  __/ |  | |_   | || | | | || (_) | |  __/| |  | | (_|  __/ | |_| | |_| |  __/ |_| |  __/
--|___|_| |_|___/\___|_|   \__| |___|_| |_|\__\___/  |_|   |_|  |_|\___\___|  \__\_\\__,_|\___|\__,_|\___|

--Remove any existing records from the PriceQueue for the new 
--price changes. Not changing the delete - insert design now.
DELETE FROM 
	FPS_PriceQueue 
FROM
		FPS_PriceQueue
	INNER JOIN
		@PriceChanges PriceChanges
			ON PriceChanges.Store = FPS_PriceQueue.Store
                                                                                                         
--price changes. Not changing the delete - insert design now.
--The insert requires a pivot of the data. Zeros could now be
--inserted if the INSERT WHERE NOT EXISTS query above had not 
--filled in any missing 12, 13, 14, or 15 fuel product price.
--INSERT INTO FPS_PriceQueue (
--	Store, UpdateStatus, Effective, Regular, RegularGC, RegularPumpOnly, RegularOverride, Plus, PlusGC, PlusPumpOnly, PlusOverride, Premium, 
--	PremiumGC, PremiumPumpOnly, PremiumOverride, Diesel, DieselGC, DieselPumpOnly, DieselOverride, Approved, Violation
--) 
SELECT
	PriceChanges.Store,
	'1' AS UpdateStatus,
    MAX(PriceChanges.EffectiveDate) AS Effective,
    MAX(CASE PriceChanges.FuelType WHEN '12' THEN Price ELSE 0 END) AS Regular,
    MAX(CASE PriceChanges.FuelType WHEN '12' THEN GiftCardPrice ELSE 0 END) AS RegularGC,
	0 AS RegularPumpOnly,
	1 AS RegularOverride,
    MAX(CASE PriceChanges.FuelType WHEN '13' THEN Price ELSE 0 END) AS Plus,
    MAX(CASE PriceChanges.FuelType WHEN '13' THEN GiftCardPrice ELSE 0 END) AS PlusGC,
	0 AS PlusPumpOnly,
	1 AS PlusOverride,
    MAX(CASE PriceChanges.FuelType WHEN '14' THEN Price ELSE 0 END) AS Premium,
    MAX(CASE PriceChanges.FuelType WHEN '14' THEN GiftCardPrice ELSE 0 END) AS PremiumGC,
	0 AS PremiumPumpOnly,
	1 AS PremiumOverride,
    MAX(CASE PriceChanges.FuelType WHEN '15' THEN Price ELSE 0 END) AS Diesel,
    MAX(CASE PriceChanges.FuelType WHEN '15' THEN GiftCardPrice ELSE 0 END) AS DieselGC,
	0 AS DieselPumpOnly,
	1 AS DieselOverride,
	CAST(0 AS BIT) AS Approved,
	0 AS Violation
INTO #PriceQueue
FROM
	@PriceChanges PriceChanges
GROUP BY
	Store
---------
INSERT INTO FPS_PriceQueue (
	Store, UpdateStatus, Effective, Regular, RegularGC, RegularPumpOnly, RegularOverride, Plus, PlusGC, PlusPumpOnly, PlusOverride, Premium, 
	PremiumGC, PremiumPumpOnly, PremiumOverride, Diesel, DieselGC, DieselPumpOnly, DieselOverride, Approved, Violation
) 
SELECT Store, UpdateStatus, Effective, Regular, RegularGC, RegularPumpOnly, RegularOverride, Plus, PlusGC, PlusPumpOnly, PlusOverride, Premium, 
	PremiumGC, PremiumPumpOnly, PremiumOverride, Diesel, DieselGC, DieselPumpOnly, DieselOverride, Approved, Violation
FROM #PriceQueue
-------------------------------------------------------------------------------------------
    ;WITH ChangePrices AS (
	SELECT
		q.Store,
		q.Effective,
		q.Regular,
		q.Plus,
		q.Premium,
		q.Diesel
	FROM
		#PriceQueue q
	)
	MERGE FPS.dbo.FPS_DailySales AS TargetTable
	USING ChangePrices AS SourceTable ON SourceTable.Store = TargetTable.StoreNumber
										AND CAST(TargetTable.[Date] AS VARCHAR(12)) = CAST(GETDATE() AS VARCHAR(12))
	WHEN NOT MATCHED BY TARGET THEN
	INSERT([Date],StoreNumber,ULPrice,PlusPrice,PremPrice,DieselPrice)
	VALUES(CAST(FLOOR(CAST(GETDATE() AS FLOAT)) AS DateTime)
				,SourceTable.Store
				,FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Regular)
				,FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Plus)
				,FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Premium)
				,FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Diesel))
	WHEN MATCHED THEN 
	UPDATE SET 
		TargetTable.ULPrice = FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Regular),
		TargetTable.PlusPrice = FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Plus),
		TargetTable.PremPrice = FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Premium),
		TargetTable.DieselPrice = FPS.dbo.fn_FPS_ConvertPrice_IntToDecimal(SourceTable.Diesel)
	;
DROP TABLE #PriceQueue

 --  ____                _                 ____        _       _       _   _                 _               
 -- / ___|_ __ ___  __ _| |_ ___    __ _  | __ )  __ _| |_ ___| |__   | \ | |_   _ _ __ ___ | |__   ___ _ __ 
 --| |   | '__/ _ \/ _` | __/ _ \  / _` | |  _ \ / _` | __/ __| '_ \  |  \| | | | | '_ ` _ \| '_ \ / _ \ '__|
 --| |___| | |  __/ (_| | ||  __/ | (_| | | |_) | (_| | || (__| | | | | |\  | |_| | | | | | | |_) |  __/ |   
 -- \____|_|  \___|\__,_|\__\___|  \__,_| |____/ \__,_|\__\___|_| |_| |_| \_|\__,_|_| |_| |_|_.__/ \___|_|   
                                                                                                           

;WITH PriceChange AS (
	SELECT
		Store,
		MAX(EffectiveDate) AS Effective
	FROM
		@PriceChanges 
	GROUP BY 
		Store 
)
DELETE FROM 
	FPS.dbo.FPS_PriceHistoryByUser
FROM
		FPS.dbo.FPS_PriceHistoryByUser PriceHistory
	INNER JOIN
		PriceChange
			ON PriceChange.Store = PriceHistory.StoreNumber
				AND PriceChange.Effective = PriceHistory.Effective


INSERT INTO FPS.dbo.FPS_PriceHistoryByUser
	(StoreNumber, Effective, Username, MoveDirection)
SELECT
	Store,
	MAX(EffectiveDate) AS Effective,
	'Kalibrate',
	0
FROM
	@PriceChanges
GROUP BY 
	Store	

 -- _   _           _       _         ____  _                   ____  _  __  __                     _   _       _     
 --| | | |_ __   __| | __ _| |_ ___  / ___|| |_ ___  _ __ ___  |  _ \(_)/ _|/ _| ___ _ __ ___ _ __ | |_(_) __ _| |___ 
 --| | | | '_ \ / _` |/ _` | __/ _ \ \___ \| __/ _ \| '__/ _ \ | | | | | |_| |_ / _ \ '__/ _ \ '_ \| __| |/ _` | / __|
 --| |_| | |_) | (_| | (_| | ||  __/  ___) | || (_) | | |  __/ | |_| | |  _|  _|  __/ | |  __/ | | | |_| | (_| | \__ \
 -- \___/| .__/ \__,_|\__,_|\__\___| |____/ \__\___/|_|  \___| |____/|_|_| |_|  \___|_|  \___|_| |_|\__|_|\__,_|_|___/
 --      |_|                                                                                                          
;WITH PriceChanges AS (
	SELECT
		Store,
        MAX(CAST(FLOOR(CAST(EffectiveDate as Float)) as SmallDateTime)) AS BusinessDate,
        MAX(CASE FuelType WHEN 12 THEN Price/1000.0 ELSE 0 END) AS Regular,
        MAX(CASE FuelType WHEN 15 THEN Price/1000.0 ELSE 0 END) AS Diesel
	FROM
		@PriceChanges
	GROUP BY
		Store

)
MERGE
	FOS.dbo.StoreAggressivenessFactors TargetTable
USING 
	PriceChanges SourceTable
		ON TargetTable.Store = SourceTable.Store
			AND TargetTable.BusinessDate = SourceTable.BusinessDate
WHEN NOT MATCHED BY TARGET THEN
	INSERT(BusinessDate, Store, PriceRE, PriceDS)
	VALUES(SourceTable.BusinessDate, SourceTable.Store, SourceTable.Regular, SourceTable.Diesel)
WHEN MATCHED THEN 
	UPDATE SET 
		TargetTable.PriceRE = SourceTable.Regular,
		TargetTable.PriceDS = SourceTable.Diesel


 -- _   _           _       _         ____  _                   ____            _        _ 
 --| | | |_ __   __| | __ _| |_ ___  / ___|| |_ ___  _ __ ___  |  _ \ ___  _ __| |_ __ _| |
 --| | | | '_ \ / _` |/ _` | __/ _ \ \___ \| __/ _ \| '__/ _ \ | |_) / _ \| '__| __/ _` | |
 --| |_| | |_) | (_| | (_| | ||  __/  ___) | || (_) | | |  __/ |  __/ (_) | |  | || (_| | |
 -- \___/| .__/ \__,_|\__,_|\__\___| |____/ \__\___/|_|  \___| |_|   \___/|_|   \__\__,_|_|
 --      |_|                                                                               
;WITH PriceChanges AS (
	SELECT
		Store,
        MAX(CAST(FLOOR(CAST(EffectiveDate as Float)) as SmallDateTime)) AS BusinessDate,
        MAX(CASE FuelType WHEN 12 THEN CAST((Price - 9)/10 AS INT) ELSE 0 END) AS Regular,
        MAX(CASE FuelType WHEN 13 THEN CAST((Price - 9)/10 AS INT) ELSE 0 END) AS Plus,
        MAX(CASE FuelType WHEN 14 THEN CAST((Price - 9)/10 AS INT) ELSE 0 END) AS Premium,
        MAX(CASE FuelType WHEN 15 THEN CAST((Price - 9)/10 AS INT) ELSE 0 END) AS Diesel
	FROM
		@PriceChanges
	GROUP BY
		Store
)
UPDATE MUSASQL.MOUSA.dbo.WebPrices  SET
	Regular = PriceChanges.Regular,
	Plus    = PriceChanges.Plus,
	Premium = PriceChanges.Premium,
	Diesel  = PriceChanges.Diesel
FROM
		MUSASQL.MOUSA.dbo.WebPrices
	INNER JOIN
		PriceChanges
			ON WebPrices.Store = PriceChanges.Store



 --  ____      _      ____ _                               __                        ___                        
 -- / ___| ___| |_   / ___| |__   __ _ _ __   __ _  ___   / _|_ __ ___  _ __ ___    / _ \ _   _  ___ _   _  ___ 
 --| |  _ / _ \ __| | |   | '_ \ / _` | '_ \ / _` |/ _ \ | |_| '__/ _ \| '_ ` _ \  | | | | | | |/ _ \ | | |/ _ \
 --| |_| |  __/ |_  | |___| | | | (_| | | | | (_| |  __/ |  _| | | (_) | | | | | | | |_| | |_| |  __/ |_| |  __/
 -- \____|\___|\__|  \____|_| |_|\__,_|_| |_|\__, |\___| |_| |_|  \___/|_| |_| |_|  \__\_\\__,_|\___|\__,_|\___|
 --                                          |___/                                                              

;WITH PriceChange AS (
	SELECT
		Store,
		MAX(EffectiveDate) AS Effective
	FROM
		@PriceChanges 
	GROUP BY
		Store
)
INSERT INTO @FPSPriceChanges (
	Store,			UpdateStatus,	Effective,			NewEffective,
	Regular,		RegularGC,		RegularPumpOnly,	RegularOverride,
	Plus,			PlusGC,			PlusPumpOnly,		PlusOverride,
	Premium,		PremiumGC,		PremiumPumpOnly,	PremiumOverride,
	Diesel,			DieselGC,		DieselPumpOnly,		DieselOverride,
	Approved,		Violation
)
SELECT
	FPS_PriceQueue.Store,
	FPS_PriceQueue.UpdateStatus,
	FPS_PriceQueue.Effective,
	CASE
		WHEN FPS_PriceQueue.Effective	< @Today THEN DATEADD(n,5,@Today)
		ELSE FPS_PriceQueue.Effective
	END AS NewEffective,
	FPS_PriceQueue.Regular,
	FPS_PriceQueue.RegularGC,
	FPS_PriceQueue.RegularPumpOnly,
	FPS_PriceQueue.RegularOverride,
	FPS_PriceQueue.Plus,
	FPS_PriceQueue.PlusGC,
	FPS_PriceQueue.PlusPumpOnly,
	FPS_PriceQueue.PlusOverride,
	FPS_PriceQueue.Premium,
	FPS_PriceQueue.PremiumGC,
	FPS_PriceQueue.PremiumPumpOnly,
	FPS_PriceQueue.PremiumOverride,
	FPS_PriceQueue.Diesel,
	FPS_PriceQueue.DieselGC,
	FPS_PriceQueue.DieselPumpOnly,
	FPS_PriceQueue.DieselOverride,
	FPS_PriceQueue.Approved,
	FPS_PriceQueue.Violation
FROM 
		dbo.FPS_PriceQueue
	INNER JOIN
		PriceChange
			ON PriceChange.Store = FPS_PriceQueue.Store
				AND PriceChange.Effective = FPS_PriceQueue.Effective
WHERE
	Approved = 0
	AND Violation <> 3
	
-- ___                                          _   ____       _           ____ _                             ____                  _   
--|_ _|_ __   ___ _ __ ___ _ __ ___   ___ _ __ | |_|  _ \ _ __(_) ___ ___ / ___| |__   __ _ _ __   __ _  ___ / ___|___  _   _ _ __ | |_ 
-- | || '_ \ / __| '__/ _ \ '_ ` _ \ / _ \ '_ \| __| |_) | '__| |/ __/ _ \ |   | '_ \ / _` | '_ \ / _` |/ _ \ |   / _ \| | | | '_ \| __|
-- | || | | | (__| | |  __/ | | | | |  __/ | | | |_|  __/| |  | | (_|  __/ |___| | | | (_| | | | | (_| |  __/ |__| (_) | |_| | | | | |_ 
--|___|_| |_|\___|_|  \___|_| |_| |_|\___|_| |_|\__|_|   |_|  |_|\___\___|\____|_| |_|\__,_|_| |_|\__, |\___|\____\___/ \__,_|_| |_|\__|
--                                                                                                |___/                                                                                                            |___/                           
MERGE
	dbo.FPS_PriceChangeCount PriceChangeCount
USING @FPSPriceChanges PriceChanges
		ON PriceChangeCount.StoreNumber = PriceChanges.Store
			AND PriceChangeCount.Day = @MonthDay
WHEN NOT MATCHED BY TARGET THEN
	INSERT(StoreNumber,			[Day],		ChangeCount) 
	VALUES(PriceChanges.Store,	@MonthDay,	1)
WHEN MATCHED THEN 
	UPDATE SET 
		PriceChangeCount.ChangeCount = PriceChangeCount.ChangeCount + 1
WHEN NOT MATCHED BY SOURCE THEN
	DELETE		
;	
-- _   _           _       _         ____       _           ___                        
--| | | |_ __   __| | __ _| |_ ___  |  _ \ _ __(_) ___ ___ / _ \ _   _  ___ _   _  ___ 
--| | | | '_ \ / _` |/ _` | __/ _ \ | |_) | '__| |/ __/ _ \ | | | | | |/ _ \ | | |/ _ \
--| |_| | |_) | (_| | (_| | ||  __/ |  __/| |  | | (_|  __/ |_| | |_| |  __/ |_| |  __/
-- \___/| .__/ \__,_|\__,_|\__\___| |_|   |_|  |_|\___\___|\__\_\\__,_|\___|\__,_|\___|
--      |_|                         

-- This approves the price changes.
UPDATE FPS_PriceQueue 
SET 
	UpdateStatus = 1, 
	Approved = 1, 
	Effective = PriceChanges.NewEffective
FROM
		dbo.FPS_PriceQueue PriceQueue 
	INNER JOIN
		@FPSPriceChanges PriceChanges 
			ON PriceQueue.Store = PriceChanges.Store 
				AND PriceQueue.Effective = PriceChanges.Effective


-- _   _           _       _         ____       _          _   _ _     _                   ____        _   _               
--| | | |_ __   __| | __ _| |_ ___  |  _ \ _ __(_) ___ ___| | | (_)___| |_ ___  _ __ _   _| __ ) _   _| | | |___  ___ _ __ 
--| | | | '_ \ / _` |/ _` | __/ _ \ | |_) | '__| |/ __/ _ \ |_| | / __| __/ _ \| '__| | | |  _ \| | | | | | / __|/ _ \ '__|
--| |_| | |_) | (_| | (_| | ||  __/ |  __/| |  | | (_|  __/  _  | \__ \ || (_) | |  | |_| | |_) | |_| | |_| \__ \  __/ |   
-- \___/| .__/ \__,_|\__,_|\__\___| |_|   |_|  |_|\___\___|_| |_|_|___/\__\___/|_|   \__, |____/ \__, |\___/|___/\___|_|   
--      |_|                                                                          |___/       |___/                     

UPDATE FPS_PriceHistoryByUser 
SET 
	Effective = PriceChanges.NewEffective
FROM
		FPS_PriceHistoryByUser (NOLOCK) PriceHistory
	INNER JOIN
		@FPSPriceChanges PriceChanges
			ON PriceHistory.StoreNumber = PriceChanges.Store 
				AND PriceHistory.Effective = PriceChanges.Effective
WHERE
	PriceChanges.NewEffective <> PriceChanges.Effective

-- _   _           _       _          ____                          _   ____       _               
--| | | |_ __   __| | __ _| |_ ___   / ___|   _ _ __ _ __ ___ _ __ | |_|  _ \ _ __(_) ___ ___  ___ 
--| | | | '_ \ / _` |/ _` | __/ _ \ | |  | | | | '__| '__/ _ \ '_ \| __| |_) | '__| |/ __/ _ \/ __|
--| |_| | |_) | (_| | (_| | ||  __/ | |__| |_| | |  | | |  __/ | | | |_|  __/| |  | | (_|  __/\__ \
-- \___/| .__/ \__,_|\__,_|\__\___|  \____\__,_|_|  |_|  \___|_| |_|\__|_|   |_|  |_|\___\___||___/
--      |_|                                                                                        

--This will fire the trigger that will:
--   1) Update CurrentFuelPriceDetails
--   2) Delete or Update the record in the PriceQueue
--   3) Insert or Update the CurrentFuelPrices table

UPDATE dbo.CurrentPrices
SET 
	Store =				PriceChanges.Store,
	UpdateStatus =		'1', 
	Effective =			PriceChanges.NewEffective, 
	Regular =			PriceChanges.Regular, 
	RegularGC =			PriceChanges.RegularGC, 
	RegularPumpOnly =	PriceChanges.RegularPumpOnly, 
	RegularOverride =	PriceChanges.RegularOverride,
	Plus =				PriceChanges.Plus, 
	PlusGC =			PriceChanges.PlusGC, 
	PlusPumpOnly =		PriceChanges.PlusPumpOnly, 
	PlusOverride =		PriceChanges.PlusOverride,
	Premium =			PriceChanges.Premium, 
	PremiumGC =			PriceChanges.PremiumGC, 
	PremiumPumpOnly =	PriceChanges.PremiumPumpOnly, 
	PremiumOverride =	PriceChanges.PremiumOverride, 
	Diesel =			PriceChanges.Diesel, 
	DieselGC =			PriceChanges.DieselGC, 
	DieselPumpOnly =	PriceChanges.DieselPumpOnly, 
	DieselOverride =	PriceChanges.DieselOverride,
	NewRegular =		PriceChanges.Regular, 
	NewPlus =			PriceChanges.Plus, 
	NewPremium =		PriceChanges.Premium, 
	NewDiesel =			PriceChanges.Diesel,
	NewRegularGC =		PriceChanges.RegularGC, 
	NewPlusGC =			PriceChanges.PlusGC, 
	NewPremiumGC =		PriceChanges.PremiumGC, 
	NewDieselGC =		PriceChanges.DieselGC,
	CurrentRegular =	CASE ISNULL(CurrentPrices.CurrentRegular, 0)	WHEN 0 THEN PriceChanges.Regular	ELSE CurrentPrices.CurrentRegular	END,
	CurrentRegularGC =	CASE ISNULL(CurrentPrices.CurrentRegularGC, 0)  WHEN 0 THEN PriceChanges.RegularGC	ELSE CurrentPrices.CurrentRegularGC	END,
	CurrentPlus =		CASE ISNULL(CurrentPrices.CurrentPlus, 0)		WHEN 0 THEN PriceChanges.Plus		ELSE CurrentPrices.CurrentPlus		END,
	CurrentPlusGC =		CASE ISNULL(CurrentPrices.CurrentPlusGC, 0)	    WHEN 0 THEN PriceChanges.PlusGC		ELSE CurrentPrices.CurrentPlusGC	END,
	CurrentPremium =	CASE ISNULL(CurrentPrices.CurrentPremium, 0)	WHEN 0 THEN PriceChanges.Premium	ELSE CurrentPrices.CurrentPremium	END,
	--CurrentPremiumGC =	CASE ISNULL(CurrentPrices.CurrentRegular, 0)	WHEN 0 THEN PriceChanges.PremiumGC	ELSE CurrentPrices.CurrentRegular	END,  --products did not align, correcting 1/21/2020
	CurrentPremiumGC =	CASE ISNULL(CurrentPrices.CurrentPremiumGC, 0)	WHEN 0 THEN PriceChanges.PremiumGC	ELSE CurrentPrices.CurrentPremiumGC	END,
	CurrentDiesel =		CASE ISNULL(CurrentPrices.CurrentDiesel, 0)	    WHEN 0 THEN PriceChanges.Diesel		ELSE CurrentPrices.CurrentDiesel	END,
	CurrentDieselGC =	CASE ISNULL(CurrentPrices.CurrentDieselGC, 0)	WHEN 0 THEN PriceChanges.DieselGC	ELSE CurrentPrices.CurrentDieselGC	END
FROM
		dbo.CurrentPrices (NOLOCK)
	INNER JOIN
		@FPSPriceChanges PriceChanges
			ON CurrentPrices.Store = PriceChanges.Store
WHERE 
	PriceChanges.UpdateStatus = 0 OR PriceChanges.UpdateStatus = 1



-- ___                     _      ____           ____                       _   ____  
--|_ _|_ __  ___  ___ _ __| |_   / ___| __ _ ___|  _ \ ___ _ __   ___  _ __| |_|___ \ 
-- | || '_ \/ __|/ _ \ '__| __| | |  _ / _` / __| |_) / _ \ '_ \ / _ \| '__| __| __) |
-- | || | | \__ \  __/ |  | |_  | |_| | (_| \__ \  _ <  __/ |_) | (_) | |  | |_ / __/ 
--|___|_| |_|___/\___|_|   \__|  \____|\__,_|___/_| \_\___| .__/ \___/|_|   \__|_____|

INSERT INTO @PMS SELECT Store, RegularPrice FROM MUSASQL.MOUSA.dbo.PMS WITH (NOLOCK);

WITH MaxCompDate AS (
	SELECT StoreNumber, MAX([Date]) AS MaxDate FROM FPS_CompetitorPrices (NOLOCK) GROUP BY StoreNumber
),
CompPrices AS(
SELECT 	
	MaxCompDate.StoreNumber			AS Store,
	ROUND(AVG(UnleadedPrice),2)		AS CompAverage,	
	MAX(UnleadedPrice)				AS CompHi,							
	MIN(UnleadedPrice)				AS CompLo
FROM
		FPS_CompetitorPrices (NOLOCK)
	INNER JOIN
		MaxCompDate
			ON FPS_CompetitorPrices.StoreNumber = MaxCompDate.StoreNumber
				AND FPS_CompetitorPrices.[Date] = MaxCompDate.MaxDate
WHERE
	FPS_CompetitorPrices.UnleadedPrice > 0
GROUP BY 
	MaxCompDate.StoreNumber						
)
INSERT INTO @PriceStrategies (
	Store,
	Strategy,
	MoveTo,
	MoveAmount,
	CompAverage,
	CompHi,		
	CompLo,
	CompOver,
	Margin
)
SELECT
	CompPrices.Store																		AS Store,
	0																						AS Strategy,
	CAST(PriceChanges.Regular - 9 AS MONEY) / 1000											AS MoveTo,
	(PriceChanges.Regular - CONVERT(INT, ISNULL(PMS.RegularPrice, 0) * 1000))/10			AS MoveAmount,
	CompPrices.CompAverage																	AS CompAverage,	
	CASE WHEN ISNULL(CompPrices.CompHi, 0) < 1.00 THEN 5.00 ELSE CompPrices.CompHi END		AS CompHi,							
	CASE WHEN ISNULL(CompPrices.CompLo, 0) < 0.10 THEN 0.50 ELSE CompPrices.CompLo END		AS CompLo,							
	ISNULL(CompPrices.CompAverage - (CAST(PriceChanges.Regular - 9 AS MONEY) / 1000), 0)	AS CompOver,
	ISNULL(PoolMargin,0)																	AS Margin
FROM
		CompPrices
	INNER JOIN
		@FPSPriceChanges PriceChanges 
			ON PriceChanges.Store = CompPrices.Store
	INNER JOIN
		dbo.FPS_DailySales (NOLOCK) DailySales
			ON DailySales.StoreNumber = CompPrices.Store
				AND DailySales.[Date] = CAST(FLOOR(CAST(PriceChanges.NewEffective AS FLOAT)) AS DATETIME)
	INNER JOIN
		@PMS PMS
			ON PMS.Store = CompPrices.Store
		
--========== Strategies ============
--		"0" for    No Change,
--		"1" for    Lead Up,
--		"2" for    Follow Up,
--		"3" for    Follow Down,
--		"4" for    Lead Down.

UPDATE @PriceStrategies
SET
	Strategy = 
	CASE WHEN MoveAmount < 0 THEN -- Lowered Price
		CASE WHEN MoveTo < CompLo THEN 4 ELSE 3 END
	ELSE
		CASE WHEN MoveTo > CompHi THEN 1 ELSE 2 END
	END
WHERE
	CompAverage <> 0;

WITH InsertUpdate AS (
SELECT 
	PriceChanges.Store																AS Store, 
	PriceChanges.NewEffective														AS Effective, 
	ISNULL(PriceStrategies.Margin, 0)												AS Margin,
	PriceStrategies.MoveTo															AS MoveTo, 
	ISNULL(PriceStrategies.MoveAmount, 0)											AS MoveAmount,
	ISNULL(PriceStrategies.CompLo, 0)												AS CompLo,
	ISNULL(PriceStrategies.CompHi, 0)												AS CompHi, 
	PriceStrategies.CompAverage														AS CompAverage, 
	PriceStrategies.Strategy														AS Strategy, 
	CASE WHEN PriceStrategies.CompOver < 0 THEN 0 ELSE PriceStrategies.CompOver END	AS CompOver
FROM 
		@FPSPriceChanges PriceChanges 
	INNER JOIN 
		@PriceStrategies PriceStrategies 
			ON PriceStrategies.Store = PriceChanges.Store
)
MERGE
	dbo.FPS_GasRpt2 GasRpt2
USING 
	InsertUpdate
		ON GasRpt2.StoreNumber		= InsertUpdate.Store
			AND GasRpt2.Effective	= InsertUpdate.Effective
			AND GasRpt2.Strategy	= InsertUpdate.Strategy
WHEN MATCHED THEN 
	UPDATE SET 
		GasRpt2.Margin			= InsertUpdate.Margin, 
		GasRpt2.CurrentPrice	= InsertUpdate.MoveTo,
		GasRpt2.PriceChange		= InsertUpdate.MoveAmount,
		GasRpt2.CompLow			= InsertUpdate.CompLo,
		GasRpt2.CompHi			= InsertUpdate.CompHi,
		GasRpt2.CompAvg			= InsertUpdate.CompAverage,
		GasRpt2.CompOver		= InsertUpdate.CompOver
WHEN NOT MATCHED THEN
	INSERT(	StoreNumber,			Effective,				Margin,						CurrentPrice,			PriceChange, 
			CompLow,				CompHi,					CompAvg,					Strategy,				CompOver ) 
	VALUES(	InsertUpdate.Store,		InsertUpdate.Effective,	InsertUpdate.Margin,		InsertUpdate.MoveTo,	InsertUpdate.MoveAmount,
			InsertUpdate.CompLo,	InsertUpdate.CompHi,	InsertUpdate.CompAverage,	InsertUpdate.Strategy,	InsertUpdate.CompOver);

WITH InsertUpdate AS (
SELECT 
	PriceChanges.Store																AS Store, 
	PriceChanges.NewEffective														AS Effective, 
	ISNULL(PriceStrategies.Margin, 0)												AS Margin,
	PriceStrategies.MoveTo															AS MoveTo, 
	ISNULL(PriceStrategies.MoveAmount, 0)											AS MoveAmount,
	ISNULL(PriceStrategies.CompLo, 0)												AS CompLo,
	ISNULL(PriceStrategies.CompHi, 0)												AS CompHi, 
	PriceStrategies.CompAverage														AS CompAverage, 
	PriceStrategies.Strategy														AS Strategy, 
	CASE WHEN PriceStrategies.CompOver < 0 THEN 0 ELSE PriceStrategies.CompOver END	AS CompOver
FROM 
		@FPSPriceChanges PriceChanges 
	INNER JOIN 
		@PriceStrategies PriceStrategies 
			ON PriceStrategies.Store = PriceChanges.Store
)	
MERGE
	dbo.FPS_FailedLeadUps FailedLeadUps
USING 
	InsertUpdate
		ON FailedLeadUps.StoreNumber = InsertUpdate.Store
			AND FailedLeadUps.Effective = InsertUpdate.Effective
WHEN MATCHED THEN 
	UPDATE SET FailedLeadUps.Strategy = InsertUpdate.Strategy, FailedLeadUps.FailLeadUP = 0
WHEN NOT MATCHED THEN
	INSERT (StoreNumber,		Effective,				Strategy,			   FailLeadUp) 
	VALUES (InsertUpdate.Store, InsertUpdate.Effective, InsertUpdate.Strategy, 0);


-- ___                     _     ____       _          _   _ _     _                   
--|_ _|_ __  ___  ___ _ __| |_  |  _ \ _ __(_) ___ ___| | | (_)___| |_ ___  _ __ _   _ 
-- | || '_ \/ __|/ _ \ '__| __| | |_) | '__| |/ __/ _ \ |_| | / __| __/ _ \| '__| | | |
-- | || | | \__ \  __/ |  | |_  |  __/| |  | | (_|  __/  _  | \__ \ || (_) | |  | |_| |
--|___|_| |_|___/\___|_|   \__| |_|   |_|  |_|\___\___|_| |_|_|___/\__\___/|_|   \__, |
--                                                                               |___/ 

WITH InsertUpdate AS (
SELECT 
	PriceChanges.Store						AS Store, 
	PriceChanges.NewEffective				AS Effective, 
	PriceChanges.Regular					AS Regular,
	ISNULL(PriceStrategies.MoveAmount, 0)	AS MoveAmount
FROM 
		@FPSPriceChanges PriceChanges 
	INNER JOIN 
		@PriceStrategies PriceStrategies 
			ON PriceStrategies.Store = PriceChanges.Store
)	
MERGE 
	dbo.FPS_PriceHistory PriceHistory
USING 
	InsertUpdate
		ON PriceHistory.StoreNumber = InsertUpdate.Store
			AND PriceHistory.Effective = InsertUpdate.Effective
WHEN MATCHED THEN 
	UPDATE SET 
		PriceHistory.CurrentPrice = InsertUpdate.Regular, 
		PriceHistory.Pricechange  = InsertUpdate.MoveAmount
WHEN NOT MATCHED THEN 
	INSERT (StoreNumber,		Effective,				CurrentPrice,		  Pricechange) 
	VALUES (InsertUpdate.Store, InsertUpdate.Effective, InsertUpdate.Regular, InsertUpdate.MoveAmount);


 -- _   _           _       _          ___       _       _             _   ____                                     _ ____       _               
 --| | | |_ __   __| | __ _| |_ ___   / _ \ _ __(_) __ _(_)_ __   __ _| | |  _ \ _ __ ___  _ __   ___  ___  ___  __| |  _ \ _ __(_) ___ ___  ___ 
 --| | | | '_ \ / _` |/ _` | __/ _ \ | | | | '__| |/ _` | | '_ \ / _` | | | |_) | '__/ _ \| '_ \ / _ \/ __|/ _ \/ _` | |_) | '__| |/ __/ _ \/ __|
 --| |_| | |_) | (_| | (_| | ||  __/ | |_| | |  | | (_| | | | | | (_| | | |  __/| | | (_) | |_) | (_) \__ \  __/ (_| |  __/| |  | | (_|  __/\__ \
 -- \___/| .__/ \__,_|\__,_|\__\___|  \___/|_|  |_|\__, |_|_| |_|\__,_|_| |_|   |_|  \___/| .__/ \___/|___/\___|\__,_|_|   |_|  |_|\___\___||___/
 --      |_|                                       |___/                                  |_|                                                    

UPDATE MUSADTSQL1.DTMUSAKalibrate.dbo.ProposedPrices
	SET IsProcessed = 1 --Mark the record as processed to indicate that the price changes have been sent to PMS
FROM
		MUSADTSQL1.DTMUSAKalibrate.dbo.ProposedPrices
	INNER JOIN
		@PriceChanges PriceChanges
			ON PriceChanges.EffectiveDate = ProposedPrices.EffectiveDate
				AND PriceChanges.Store = CAST(ProposedPrices.SiteId AS INT)
WHERE
    IsProcessed = 0


-- ___                     _     _       _          ____                       
--|_ _|_ __  ___  ___ _ __| |_  (_)_ __ | |_ ___   |  _ \ __ _  __ _  ___ _ __ 
-- | || '_ \/ __|/ _ \ '__| __| | | '_ \| __/ _ \  | |_) / _` |/ _` |/ _ \ '__|
-- | || | | \__ \  __/ |  | |_  | | | | | || (_) | |  __/ (_| | (_| |  __/ |   
--|___|_| |_|___/\___|_|   \__| |_|_| |_|\__\___/  |_|   \__,_|\__, |\___|_|   
--                                                             |___/          

SELECT
	Store,
	PriceChanges.EffectiveDate,
	FuelType,
	Price,
	GiftCardPrice
INTO #PAGERPRICECHANGES
FROM 
	@PriceChanges PriceChanges
INNER JOIN 
	MUSADTSQL1.DTMUSAKalibrate.dbo.ProposedPrices
ON 
	ProposedPrices.EffectiveDate = Pricechanges.EffectiveDate
	AND CAST(ProposedPrices.SiteID AS INT) = PriceChanges.Store
	AND Pricechanges.FuelType = ProposedPrices.Productcode 
WHERE 
	IsProcessed = 1
ORDER BY 
	Store


SELECT @COUNTER = COUNT(Store) 
FROM 
	#PAGERPRICECHANGES


WHILE (@COUNTER > 0)
BEGIN


SELECT @ADDRESS = Email_Adr
FROM 
	STORES
INNER JOIN
	(SELECT TOP 1 Store FROM #PAGERPRICECHANGES) PAGERPRICECHANGES
ON 
	PAGERPRICECHANGES.Store = STORES.StoreNumber

If @ADDRESS Is NULL Set @ADDRESS = ''


SET @XML= CAST(
(SELECT 
	PAGERPRICECHANGES.Store					AS 'td',
	'',
	CAST(EffectiveDate AS VARCHAR(50))		AS 'td',
	'',
	CURRENTFUELTYPES.FuelDescription		AS 'td',
	'',
	CAST(Price AS VARCHAR(50))				AS 'td'
FROM 
	#PAGERPRICECHANGES PAGERPRICECHANGES
INNER JOIN
	(SELECT TOP 1 Store FROM #PAGERPRICECHANGES) STORE
ON 
	STORE.Store = PAGERPRICECHANGES.Store
INNER JOIN 
	CURRENTFUELTYPES 
ON 
	CURRENTFUELTYPES.FuelType = PAGERPRICECHANGES.FuelType
ORDER BY 
	PAGERPRICECHANGES.Store, PAGERPRICECHANGES.FuelType
FOR XML PATH('tr'), ELEMENTS)
AS NVARCHAR(MAX))


SET @BODY = 
	'<HTML><BODY><H1>PRICE CHANGE NOTIFICATION</TITLE></H1>
	<H2>PRICE CHANGE INFORMATION:</H2>
	<table border = 1>
	<tr>
	<th>Store</th>
	<th>Effective Date (Central Time)</th>
	<th>Fuel Description</th>
	<th>Price</th>
	</tr>'

SET @BODY = @BODY + @XML + '</table></body></html>'


EXEC MUSASQL.Pager.dbo.spInsertAdHocPages @ADDRESS, @BODY, 'FUEL PRICE CHANGE!!', 1, '', '', '', '', 'fuelpricing@murphyusa.com'


DELETE FROM 
	#PAGERPRICECHANGES 
WHERE 
	Store IN 
		(SELECT TOP 1 Store FROM #PAGERPRICECHANGES)

SELECT @COUNTER = COUNT(STORE) 
FROM 
	#PAGERPRICECHANGES

END

DROP TABLE #PAGERPRICECHANGES



GO

GRANT EXECUTE ON [dbo].[DT_KalibratePriceChange] TO [SP_Execute] AS [dbo]
GO


