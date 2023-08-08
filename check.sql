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
) GO
DECLARE @PMS AS TABLE (
	Store			INT NOT NULL,
	RegularPrice	MONEY NULL
) GO

