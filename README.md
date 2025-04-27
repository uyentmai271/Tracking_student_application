# International Student Application Tracking System

## Project Overview
A comprehensive database system designed to track international student applications, manage document submissions, and ensure compliance with immigration requirements through SEVIS record tracking. This project was developed as part of the CSC625 Database course.

## Project Objectives
- Track student applications and their statuses
- Monitor document submissions required for admission
- Manage SEVIS records and ensure compliance with immigration regulations
- Link international students with their corresponding SEVIS records
- Generate reports and insights about the application process

## Technologies Used
- Microsoft SQL Server
- SQL scripting for data manipulation and stored procedures
- Temporary tables for data processing
- String matching algorithms for record linkage

## Database Schema
The system includes three core database tables:
1. Student Table: Contains student identification and contact information
2. Application Table: Tracks application details including term, major, and decision status
3. SEVIS Table: Manages international student SEVIS records and immigration status

## Installation and Setup

### Prerequisites
- Microsoft SQL Server (2019 or later recommended)
- SQL Server Management Studio

### Installation Steps
1. Clone this repository
2. Run the scripts in the following order:
   - schema/create_tables.sql
   - data/insert_data.sql
   - procedures/name_matching.sql

## Key Features
- Sophisticated name-matching algorithm to link SEVIS records with student records
- Comprehensive reporting on match status
- Robust security measures to protect sensitive data
