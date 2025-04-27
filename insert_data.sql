USE StudentAdmissionDB;
GO

-- Insert into Student
INSERT INTO Student (
    Student_ID, First_Name, Last_Name, Email_Address, 
    Phone_Cell_Country_Code, Phone_Cell_Number
)
SELECT DISTINCT
    School_ID AS Student_ID,
    First_Name AS First_Name,
    Last_Name AS Last_Name,
    Email_Email_address AS Email_Address,
    Phone_Cell_Country_Code,
	Phone_Cell_Number
FROM Staging_LSUS
WHERE School_ID IS NOT NULL
  AND NOT EXISTS (
        SELECT 1 FROM Student WHERE Student.Student_ID = Staging_LSUS.School_ID
    );

-- Insert into Application
INSERT INTO Application (
    Student_ID, Application_Submitted_Date, Application_Term, Application_Major,
    Decision_Status, Cumulative_GPA, Last_60_Hours_GPA, Graduate_GPA,
    All_Transcripts_Received, Citizenship_Status, Country_Of_Citizenship
)
SELECT
    School_ID,
    Application_Submitted_Date,
    Application_Term,
    Application_Major,
    Decision_status_guid AS Decision_Status,
    Cumulative_GPA,
    Last_60_Hours_GPA,
    Graduate_GPA,
    All_Transcripts_Received,
    Citizenship_Status,
    Country_of_Citizenship
FROM Staging_LSUS;

-- Insert into SEVIS
INSERT INTO SEVIS (
    SEVIS_ID, Student_ID, Class_Of_Admission, Program_Start_Date,
    Program_End_Date, Current_Status, Last_Status_Change
)
SELECT
    SEVIS_ID,
    Student_ID,
    Class_Of_Admission,
    Program_Start_Date,
    Program_End_Date,
    Current_Status,
    Last_Status_Change
FROM Staging_SEVIS
WHERE NOT EXISTS (
    SELECT 1 FROM SEVIS WHERE SEVIS.SEVIS_ID = Staging_SEVIS.SEVIS_ID
);

