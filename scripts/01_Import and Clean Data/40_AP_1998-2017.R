
###'######################################################################
###'
###' Import and clean data files 
###' 
###' - Postsecondary Preparation
###' 
###'   (3) AP 
###'   
###' 
###' 20181027 JoonHo Lee
###' 20190426 JoonHo Lee - Update 2017-18 data
###' 
###' 

###'######################################################################
###'
###' Basic settings
###'
###'

### Start with a clean slate
gc()            # force R to release memory it is no longer using
rm(list=ls())   # delete all the objects in the workspace


### Set working directory 
work_dir <- c("~/SACS")
setwd(work_dir)


### Set a directory containing large data files
data_dir <- c("D:/Data/LCFF/School_Performance/Postsecondary_Preparation/AP")


### Call libraries
library(tidyverse)
library(readxl)
library(Hmisc)
library(ldat)
library(foreign)


### Call functions
list.files("functions", full.names = TRUE) %>% walk(source)



###'######################################################################
###'
###' Loop over years: 9899-1718 
###' 
###' 

years <- c(sprintf("%02d", seq(98, 99)), sprintf("%02d", seq(0, 17))) 

for (i in seq_along(years)){
  
  
  ###'######################################################################
  ###'
  ###' Assign year number & filetype
  ###' 
  ###' 
  
  year_num <- years[i]
  
  
  
  ###'######################################################################
  ###'
  ###' Import raw excel file
  ###'
  ###'
  
  ### Set data containing working directory
  setwd(data_dir)
  
  
  ### Assign filenames
  if (year_num != c("17")){
    
    filename <- paste0("ap", years[i], years[i + 1]) 
    
  } else if (year_num == c("17")){
    
    filename <- paste0("ap", year_num, as.numeric(year_num) + 1)
    
  }
  
  
  
  ### Import data file
  if (year_num %in% sprintf("%02d", c(98:99, 0:12))){
    
    df <- read_excel(paste0(filename, ".xls"), 
                     sheet = 1, skip = 2)
    
  } else if (year_num %in% sprintf("%02d", c(13:17))){
    
    df <- read_excel(paste0(filename, ".xls"), 
                     sheet = 1, skip = 0)
    
  }
  
  classmode(df, everything())
  
  
  ### Convert empty strings to NA
  df <- df %>% mutate_all(funs(empty_as_na)) 
  
  

  ###'######################################################################
  ###'
  ###' Assign variable names
  ###'
  ###'
  
  classmode(df, everything())
  
  if (year_num %in% sprintf("%02d", c(98:99, 0:5))){
    
    names(df) <- c("CountyCode", "DistrictCode", "SchoolCode", 
                   "CountyName", "DistrictName", "SchoolName", 
                   "N_Enroll_GR11", "N_Enroll_GR12", "N_Enroll_GR11_12",  
                   "N_ExamTakers", "N_Exams_Taken", 
                   "N_Exams_3above", "N_Exams_Scr1", "N_Exams_Scr2", 
                   "N_Exams_Scr3", "N_Exams_Scr4", "N_Exams_Scr5")
    
  } else if (year_num %in% sprintf("%02d", c(6:12))){
    
    names(df) <- c("CountyCode", "DistrictCode", "SchoolCode", 
                   "CountyName", "DistrictName", "SchoolName", 
                   "N_Enroll_GR11", "N_Enroll_GR12", "N_Enroll_GR11_12",  
                   "N_ExamTakers", 
                   "N_Exams_Scr1", "N_Exams_Scr2", 
                   "N_Exams_Scr3", "N_Exams_Scr4", "N_Exams_Scr5")
    
  } else if (year_num %in% sprintf("%02d", c(13:16))){
    
    names(df) <- c("CDS", "ReportType", 
                   "SchoolName", "DistrictName", "CountyName", 
                   "N_Enroll_GR10_12", "N_Enroll_GR12", "N_ExamTakers",
                   "N_Exams_Scr1", "N_Exams_Scr2", 
                   "N_Exams_Scr3", "N_Exams_Scr4", "N_Exams_Scr5")
    
  } else if (year_num %in% sprintf("%02d", c(17))){
    
    names(df) <- c("CDS", 
                   "CountyCode", "DistrictCode", "SchoolCode", 
                   "ReportType", 
                   "SchoolName", "DistrictName", "CountyName", 
                   "N_Enroll_GR12", "N_Enroll_GR10_12", "N_ExamTakers",
                   "N_Exams_Scr1", "N_Exams_Scr2", 
                   "N_Exams_Scr3", "N_Exams_Scr4", "N_Exams_Scr5", 
                   "Year")
    
  } 
  
  
  
  ###'######################################################################
  ###'
  ###' Add a Year variable
  ###'
  ###'
  
  df <- df %>%
    mutate(Year = ifelse(as.numeric(year_num) < 20, 
                         as.numeric(year_num) + 2000, 
                         as.numeric(year_num) + 1900)) %>%
    dplyr::select(Year, everything())
  
  
  
  ###'######################################################################
  ###'
  ###' CDS code 
  ###' 
  ###' 
  
  if (year_num %in% sprintf("%02d", c(13:17))){
    
    ### Check number of characters: should be 14
    table(nchar(df$CDS))
    
    
    ### Substring County, District, School Codes
    df <- df %>%
      mutate(CountyCode = substr(CDS, start = 1, stop = 2), 
             DistrictCode = substr(CDS, start = 3, stop = 7), 
             SchoolCode = substr(CDS, start = 8, stop = 14))
    
    
    ### Check distributions
    tabdf(df, CountyCode)
    tabdf(df, DistrictCode)
    tabdf(df, SchoolCode)
    
  } 
  
  
  ### Convert character to numeric
  df <- df %>%
    mutate_at(.vars = c("CountyCode", "DistrictCode", "SchoolCode"), 
              .funs = as.numeric)
  
  classmode(df, everything())
  
  
  
  ###'######################################################################
  ###'
  ###' Verify CDS codes
  ###'
  ###'
  
  ### Check the number of digits
  table(nchar(df$CountyCode))
  table(nchar(df$DistrictCode))
  table(nchar(df$SchoolCode))
  
  
  ###' Substring County, District, School Codes
  ###' If DistrictCode > 5, it means that the Dcodes are concatenated with Ccodes
  
  if (all(unique(nchar(df$DistrictCode)) != 5)) {
    
    df <- df %>%
      mutate(DistrictCode = as.numeric(str_sub(df$DistrictCode, -5, -1)))
    
  }
  
  
  
  ###'######################################################################
  ###'
  ###' Convert variables to numeric
  ###'
  ###'
  
  ### Variables to convert
  classmode(df, everything())
  
  to_numeric <- c(names(df)[grepl("N_", names(df))], 
                  names(df)[grepl("Avg_", names(df))], 
                  names(df)[grepl("PCT_", names(df))])
  
  
  ### Convert selected columns to numeric
  df[, to_numeric] <- df[, to_numeric] %>% 
    mutate_all(.funs = as.numeric)
  
  classmode(df, everything())
  
  
  
  
  ###'######################################################################
  ###'
  ###' Recode missing values in N_ExamTakers with zero
  ###'
  ###'
  
  ### Check the distribution
  nrow(df)
  tabdf(df, N_ExamTakers)
  
  
  ### Index missing values and convert them to zero
  idx <- is.na(df$N_ExamTakers)
  df$N_ExamTakers[idx] <- 0
  
  
  
  ###'######################################################################
  ###'
  ###' Rearrange rows and columns
  ###'
  ###'
  
  if (year_num %in% sprintf("%02d", c(13:17))){
    
    classmode(df, everything())
    
    df <- df %>%
      select(-CDS) %>%
      select(Year, ReportType, 
             CountyCode, DistrictCode, SchoolCode, 
             CountyName, DistrictName, SchoolName, 
             everything()) %>%
      arrange(ReportType, CountyCode, DistrictCode, SchoolCode)
    
  }
  
  
  
  ###'######################################################################
  ###' 
  ###' Save data objects
  ###' 
  ###' 
  
  ### Set data containing working directory
  setwd(data_dir)
  
  
  ### Save the resulting dataframe
  save(df, file = paste0(filename, "_cleaned", ".rda"))
  write.dta(df, file = paste0(filename, "_cleaned", ".dta"))
  
  
  
  ###'######################################################################
  ###' 
  ###' Print the progress  
  ###' 
  
  cat(paste0("Year ", years[i], " completed", "\n"))
  
  
} # End of loop over years
