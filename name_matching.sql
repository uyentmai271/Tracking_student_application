USE StudentAdmissionDB;
GO

/*
=======================================================================
SETUP: Create temporary tables for processing
=======================================================================
*/
BEGIN TRY
    -- Clean up any existing temp tables
    DROP TABLE IF EXISTS #TempSEVIS;
    DROP TABLE IF EXISTS #LatestSEVIS;
    DROP TABLE IF EXISTS #PotentialMatches;
    DROP TABLE IF EXISTS #NameComponentMatches;

    -- Table to hold all imported SEVIS records
    CREATE TABLE #TempSEVIS (
        Record_ID INT IDENTITY(1,1) PRIMARY KEY,
        SEVIS_ID VARCHAR(11) NOT NULL,
        Last_Name NVARCHAR(100),
        First_Name NVARCHAR(100),
        Class_Of_Admission NVARCHAR(50),
        Program_Start_Date DATE,
        Program_End_Date DATE,
        Current_Status NVARCHAR(50),
        Last_Status_Change DATE,
        Is_Latest BIT DEFAULT 0
    );

    -- Table to hold only the most recent SEVIS record for each student
    CREATE TABLE #LatestSEVIS (
        SEVIS_ID VARCHAR(11) PRIMARY KEY,
        Last_Name NVARCHAR(100),
        First_Name NVARCHAR(100),
        Class_Of_Admission NVARCHAR(50),
        Program_Start_Date DATE,
        Program_End_Date DATE,
        Current_Status NVARCHAR(50),
        Last_Status_Change DATE
    );

    -- Table to store potential matches between Students and SEVIS records
    CREATE TABLE #PotentialMatches (
        Match_ID INT IDENTITY(1,1) PRIMARY KEY,
        Student_ID VARCHAR(9),
        SEVIS_ID VARCHAR(11),
        Match_Score INT,
        Match_Type NVARCHAR(50),
        Is_Confirmed BIT DEFAULT 0
    );

    -- Create indexes to speed up matching
    CREATE INDEX IX_Student_Name ON Student(Last_Name, First_Name);
    CREATE INDEX IX_TempSEVIS_Name ON #TempSEVIS(Last_Name, First_Name);
    
    PRINT 'Temporary tables created successfully';
END TRY
BEGIN CATCH
    PRINT 'Error during setup: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
DATA LOADING: Import and prepare SEVIS data
=======================================================================
*/
BEGIN TRY
    -- Step 1: Load raw SEVIS data into staging table
    INSERT INTO #TempSEVIS (
        SEVIS_ID, Last_Name, First_Name, 
        Class_Of_Admission, Program_Start_Date, 
        Program_End_Date, Current_Status, Last_Status_Change
    )
    SELECT 
        SEVIS_ID,
        LTRIM(RTRIM([Surname_Primary_Name])) AS Last_Name,
        LTRIM(RTRIM([Given_Name])) AS First_Name,
        [Class_of_Admission] AS Class_Of_Admission,
        CAST([Program_Start_Date] AS DATE),
        CAST([Program_End_Date] AS DATE),
        [Status] AS Current_Status,
        CAST([Last_Status_Change] AS DATE)
    FROM Staging_SEVIS;

    -- Step 2: Identify the most recent record for each SEVIS ID
    WITH LatestRecords AS (
        SELECT 
            Record_ID,
            ROW_NUMBER() OVER (
                PARTITION BY SEVIS_ID 
                ORDER BY Last_Status_Change DESC, Program_Start_Date DESC
            ) AS RowNum
        FROM #TempSEVIS
    )
    UPDATE #TempSEVIS
    SET Is_Latest = 1
    FROM #TempSEVIS t
    JOIN LatestRecords l ON t.Record_ID = l.Record_ID
    WHERE l.RowNum = 1;

    -- Step 3: Populate the latest records table
    INSERT INTO #LatestSEVIS
    SELECT 
        SEVIS_ID, Last_Name, First_Name,
        Class_Of_Admission, Program_Start_Date,
        Program_End_Date, Current_Status, Last_Status_Change
    FROM #TempSEVIS
    WHERE Is_Latest = 1;

    PRINT 'Loaded ' + CAST(@@ROWCOUNT AS VARCHAR) + ' SEVIS records';
END TRY
BEGIN CATCH
    PRINT 'Error loading SEVIS data: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
MATCHING PROCESS: Find matches between Students and SEVIS records
=======================================================================
*/
BEGIN TRY
    -- Create helper table for name component analysis
    CREATE TABLE #NameComponentMatches (
        Student_ID VARCHAR(9),
        SEVIS_ID VARCHAR(11),
        LastNameComponentsMatch INT,
        FirstNameComponentsMatch INT,
        LastNameMatchScore FLOAT,
        FirstNameMatchScore FLOAT,
        TotalComponents INT
    );
    
    -- Analyze name components for potential matches
    INSERT INTO #NameComponentMatches
    SELECT 
        s.Student_ID,
        ls.SEVIS_ID,
        -- Count matching last name components
        (
            SELECT COUNT(*) 
            FROM (
                SELECT value FROM STRING_SPLIT(s.Last_Name, ' ')
                INTERSECT
                SELECT value FROM STRING_SPLIT(ls.Last_Name, ' ')
            ) AS matches
        ) AS LastNameComponentsMatch,
        
        -- Count matching first name components
        (
            SELECT COUNT(*) 
            FROM (
                SELECT value FROM STRING_SPLIT(s.First_Name, ' ')
                INTERSECT
                SELECT value FROM STRING_SPLIT(ls.First_Name, ' ')
            ) AS matches
        ) AS FirstNameComponentsMatch,
        
        -- Calculate match percentages
        CAST((
            SELECT COUNT(*) FROM (
                SELECT value FROM STRING_SPLIT(s.Last_Name, ' ')
                INTERSECT
                SELECT value FROM STRING_SPLIT(ls.Last_Name, ' ')
            ) AS matches
        ) AS FLOAT) / NULLIF((
            SELECT COUNT(*) FROM STRING_SPLIT(s.Last_Name, ' ')
        ), 0) AS LastNameMatchScore,
        
        CAST((
            SELECT COUNT(*) FROM (
                SELECT value FROM STRING_SPLIT(s.First_Name, ' ')
                INTERSECT
                SELECT value FROM STRING_SPLIT(ls.First_Name, ' ')
            ) AS matches
        ) AS FLOAT) / NULLIF((
            SELECT COUNT(*) FROM STRING_SPLIT(s.First_Name, ' ')
        ), 0) AS FirstNameMatchScore,
        
        -- Total components for weighting
        (SELECT COUNT(*) FROM STRING_SPLIT(s.Last_Name, ' ')) +
        (SELECT COUNT(*) FROM STRING_SPLIT(s.First_Name, ' ')) AS TotalComponents
    FROM Student s
    CROSS JOIN #LatestSEVIS ls
    WHERE EXISTS (
        SELECT 1 FROM STRING_SPLIT(s.Last_Name, ' ') AS s1
        JOIN STRING_SPLIT(ls.Last_Name, ' ') AS s2 ON LOWER(s1.value) = LOWER(s2.value)
    ) OR EXISTS (
        SELECT 1 FROM STRING_SPLIT(s.First_Name, ' ') AS s1
        JOIN STRING_SPLIT(ls.First_Name, ' ') AS s2 ON LOWER(s1.value) = LOWER(s2.value)
    );

    -- Insert matches with scoring
    INSERT INTO #PotentialMatches (Student_ID, SEVIS_ID, Match_Score, Match_Type)
    SELECT 
        Student_ID,
        SEVIS_ID,
        -- Calculate overall match score (weighted 60% last name, 40% first name)
        CASE
            WHEN LastNameMatchScore = 1 AND FirstNameMatchScore = 1 THEN 100
            WHEN LastNameMatchScore = 1 THEN 90
            WHEN FirstNameMatchScore = 1 THEN 85
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.9 THEN 80
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.7 THEN 70
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.5 THEN 60
            ELSE 50
        END AS Match_Score,
        
        -- Describe match quality
        CASE
            WHEN LastNameMatchScore = 1 AND FirstNameMatchScore = 1 THEN 'Perfect match'
            WHEN LastNameMatchScore = 1 THEN 'Perfect last name match'
            WHEN FirstNameMatchScore = 1 THEN 'Perfect first name match'
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.9 THEN 'Strong match'
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.7 THEN 'Good match'
            WHEN (LastNameMatchScore * 0.6 + FirstNameMatchScore * 0.4) >= 0.5 THEN 'Partial match'
            ELSE 'Weak match'
        END AS Match_Type
    FROM #NameComponentMatches
    WHERE LastNameComponentsMatch > 0 OR FirstNameComponentsMatch > 0;

    PRINT 'Found ' + CAST(@@ROWCOUNT AS VARCHAR) + ' potential matches';
    
    -- Clean up
    DROP TABLE #NameComponentMatches;
END TRY
BEGIN CATCH
    IF OBJECT_ID('tempdb..#NameComponentMatches') IS NOT NULL 
        DROP TABLE #NameComponentMatches;
    PRINT 'Error in matching process: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
MATCH RESOLUTION: Select the best matches
=======================================================================
*/
BEGIN TRY
    -- Create a table to hold the final matches
    CREATE TABLE #FinalMatches (
        Student_ID VARCHAR(9) PRIMARY KEY,
        SEVIS_ID VARCHAR(11) UNIQUE,
        Match_Score INT,
        Match_Type NVARCHAR(50)
    );

    -- Step 1: For each student, select their best SEVIS match
    WITH BestStudentMatches AS (
        SELECT 
            Student_ID,
            SEVIS_ID,
            Match_Score,
            Match_Type,
            ROW_NUMBER() OVER (
                PARTITION BY Student_ID 
                ORDER BY Match_Score DESC, SEVIS_ID
            ) AS RankByStudent
        FROM #PotentialMatches
    ),
    
    -- Step 2: For each SEVIS record, select the best student match
    BestSEVISMatches AS (
        SELECT 
            Student_ID,
            SEVIS_ID,
            Match_Score,
            Match_Type,
            ROW_NUMBER() OVER (
                PARTITION BY SEVIS_ID 
                ORDER BY Match_Score DESC, Student_ID
            ) AS RankBySEVIS
        FROM BestStudentMatches
        WHERE RankByStudent = 1
    )
    
    -- Step 3: Insert only mutually best matches
    INSERT INTO #FinalMatches
    SELECT 
        Student_ID,
        SEVIS_ID,
        Match_Score,
        Match_Type
    FROM BestSEVISMatches
    WHERE RankBySEVIS = 1;

    PRINT 'Resolved ' + CAST(@@ROWCOUNT AS VARCHAR) + ' final matches';
END TRY
BEGIN CATCH
    PRINT 'Error in match resolution: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
REPORTING: Show matching results
=======================================================================
*/
BEGIN TRY
    -- Show final matches
    SELECT 
        s.Student_ID,
        s.Last_Name AS Student_LastName,
        s.First_Name AS Student_FirstName,
        fm.SEVIS_ID,
        ls.Last_Name AS SEVIS_LastName,
        ls.First_Name AS SEVIS_FirstName,
        fm.Match_Score,
        fm.Match_Type,
        'Confirmed' AS Match_Status
    FROM #FinalMatches fm
    JOIN Student s ON fm.Student_ID = s.Student_ID
    JOIN #LatestSEVIS ls ON fm.SEVIS_ID = ls.SEVIS_ID
    ORDER BY fm.Match_Score DESC, s.Last_Name, s.First_Name;

    -- Show unmatched students
    SELECT 
        s.Student_ID,
        s.Last_Name,
        s.First_Name,
        'No match found' AS Match_Status
    FROM Student s
    LEFT JOIN #FinalMatches fm ON s.Student_ID = fm.Student_ID
    WHERE fm.Student_ID IS NULL
    ORDER BY s.Last_Name, s.First_Name;

    -- Show unused SEVIS records
    SELECT 
        ls.SEVIS_ID,
        ls.Last_Name,
        ls.First_Name,
        'Not assigned' AS Match_Status
    FROM #LatestSEVIS ls
    LEFT JOIN #FinalMatches fm ON ls.SEVIS_ID = fm.SEVIS_ID
    WHERE fm.SEVIS_ID IS NULL
    ORDER BY ls.Last_Name, ls.First_Name;
END TRY
BEGIN CATCH
    PRINT 'Error during reporting: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
DATA IMPORT: Save matches to database
=======================================================================
*/
BEGIN TRY
    -- Clear existing data if needed
    -- DELETE FROM SEVIS;
    
    -- Insert final matches
    INSERT INTO SEVIS (
        SEVIS_ID, Student_ID, Class_Of_Admission, 
        Program_Start_Date, Program_End_Date, Current_Status, Last_Status_Change
    )
    SELECT 
        fm.SEVIS_ID,
        fm.Student_ID,
        ls.Class_Of_Admission,
        ls.Program_Start_Date,
        ls.Program_End_Date,
        ls.Current_Status,
        ls.Last_Status_Change
    FROM #FinalMatches fm
    JOIN #LatestSEVIS ls ON fm.SEVIS_ID = ls.SEVIS_ID;

    PRINT 'Successfully imported ' + CAST(@@ROWCOUNT AS VARCHAR) + ' records';
END TRY
BEGIN CATCH
    PRINT 'Error during data import: ' + ERROR_MESSAGE();
    THROW;
END CATCH
GO

/*
=======================================================================
CLEANUP: Remove temporary tables
=======================================================================
*/
BEGIN TRY
    DROP TABLE IF EXISTS #TempSEVIS;
    DROP TABLE IF EXISTS #LatestSEVIS;
    DROP TABLE IF EXISTS #PotentialMatches;
    DROP TABLE IF EXISTS #FinalMatches;
    PRINT 'Temporary tables cleaned up';
END TRY
BEGIN CATCH
    PRINT 'Error during cleanup: ' + ERROR_MESSAGE();
END CATCH
GO