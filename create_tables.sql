USE StudentAdmissionDB;
GO

CREATE TABLE Student (
    Student_ID VARCHAR(9) PRIMARY KEY,
    First_Name NVARCHAR(100),
    Last_Name NVARCHAR(100),
    Email_Address NVARCHAR(255),
    Phone_Cell_Country_Code INT,
    Phone_Cell_Number BIGINT
);

CREATE TABLE Application (
    Student_ID VARCHAR(9),
    Application_Submitted_Date DATE,
    Application_Term NVARCHAR(50),
    Application_Major NVARCHAR(255),
    Decision_Status NVARCHAR(100),
    Cumulative_GPA FLOAT,
    Last_60_Hours_GPA FLOAT,
    Graduate_GPA FLOAT,
    All_Transcripts_Received BIT,
    Citizenship_Status NVARCHAR(50),
    Country_Of_Citizenship NVARCHAR(100),
	PRIMARY KEY (Student_ID, Application_Term),
    FOREIGN KEY (Student_ID) REFERENCES Student(Student_ID)
);

CREATE TABLE SEVIS (
    SEVIS_ID VARCHAR(11) PRIMARY KEY,
    Student_ID VARCHAR(9) NULL,
    Class_Of_Admission NVARCHAR(50),
    Program_Start_Date DATE,
    Program_End_Date DATE,
    Current_Status NVARCHAR(50),
    Last_Status_Change DATE,
    FOREIGN KEY (Student_ID) REFERENCES Student(Student_ID)
);
