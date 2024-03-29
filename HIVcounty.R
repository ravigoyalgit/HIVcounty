options(tigris_use_cache = TRUE)

library('MASS')
library('tidyverse')
library('readxl')
library('kableExtra')
library('eeptools')
library('geepack')
library('caret')
library('tidycensus')
library('zipcodeR')
library('leaflet')
library('classInt')
library('RColorBrewer')
library('gtsummary')
library('lme4')
library('glmmLasso')
library('nlme')
library('mapview')
library('tidycensus')
library('here')
data("zip_code_db")
source("HIVcounty_func.R")

# directory_loc = "/Users/ravigoyal/Dropbox/Academic/Research/Projects/HIVcounty/Clark_County_data/"
directory_loc = paste0(here(),'/')
result_file_loc = here('Results/')

county_demo_file_subloc = "Nevada_eHARS_demographics_073123.csv"
county_zip_file_subloc =  "Nevada_eHARS_by_zip.csv_073123.csv"
#county_test_file_subloc = "Clark_County_data/2023 SNHD testing sites.xlsx"
county_test_file_subloc = "2023 SNHD testing sites.xlsx"

county_zip_list = search_county("Clark", "NV") %>% pull(zipcode)
county_zip_list_full = search_county("Clark", "NV")

# load("~/Documents/Projects/Nevada/data requests/NV_Data_Processing_Scripts/reference_files/CC_zips.Rdata")

# all.equal(county_zip_list_full,cc.zips)
# identical(county_zip_list_full$zipcode,cc.zips$zipcode)

#county_demo_file_subloc = "San_Diego_data/sd_county_demographics.csv"
#county_zip_file_subloc = "San_Diego_data/sd_county_by_zip.csv"
#county_vl_file_subloc = "San_Diego_data/sd_viral_suppression_by_year.csv"

testing_site_bool = TRUE

#######

################
## Create analytic dataset
################

county.df  = read_county_data(directory_loc = directory_loc,
                              county_demo_file_subloc = county_demo_file_subloc,
                              county_zip_file_subloc = county_zip_file_subloc
                              # county_zip_list = county_zip_list
) 

#Population - B01003_001 Estimate!!Total TOTAL POPULATION
#HISPANIC - B03001_003 Estimate!!Total:!!Hispanic or Latino: HISPANIC OR LATINO ORIGIN BY SPECIFIC ORIGIN tract
#EDUCATION - B16010_015 Estimate!!Total:!!High school graduate (includes equivalency): EDUCATIONAL ATTAINMENT AND EMPLOYMENT STATUS BY LANGUAGE SPOKEN AT HOME FOR THE POPULATION 25 YEARS AND OVER
#RACE - B02001_002 Estimate!!Total:!!White alone RACE
#POVERY - B17001_002 Estimate!!Total:!!Income in the past 12 months below poverty level: POVERTY STATUS IN THE PAST 12 MONTHS BY SEX BY AGE
#INCOME - B08121_001 Estimate!!Median earnings in the past 12 months --!!Total:MEDIAN EARNINGS IN THE PAST 12 MONTHS (IN 2021 
#Employment - B23025_002 Estimate!!Total:!!In labor force: EMPLOYMENT STATUS FOR THE POPULATION 16 YEARS AND OVER

# x = load_variables(2021, "acs5", cache = TRUE)
# x %>% View()

zipcode.df <- get_acs(geography = "zcta",
                      variables = c("B01003_001",
                                    "B03001_003",
                                    "B16010_015",
                                    "B02001_002",
                                    "B17001_002",
                                    "B08121_001",
                                    "B23025_002"),
                      year = 2021,
                      zcta = county_zip_list) 

zipcode_wide.df = zipcode.df %>%
  select(GEOID, variable, estimate) %>%
  # mutate(GEOID = as.numeric(GEOID)) %>%
  pivot_wider(names_from = variable,
              values_from = estimate) %>%
  rename(zc_population = B01003_001,
         zc_hispanic = B03001_003, 
         zc_education = B16010_015, 
         zc_white = B02001_002,
         zc_poverty = B17001_002,
         zc_income = B08121_001,
         zc_employment = B23025_002)

county.df = left_join(county.df, zipcode_wide.df,
                      by = c( "rsd_zip_cd" = "GEOID"))

################
## Generate outcomes
################

county.df = county.df %>%
  mutate(outcome_diagnosis = case_when(
    `Disease Category` == "HIV ONLY (HIV, STAGE 1 OR 2)" ~ 0,
    `Disease Category` == "HIV AND AIDS SIMULTANEOUSLY (HIV, STAGE 3)" ~ 1,
    `Disease Category` == "HIV AND LATER AIDS (HIV, STAGE 3)" ~ 1,
    TRUE ~ NA_real_),
    outcome_diagnosis_factor = factor(outcome_diagnosis,levels = c(0,1), labels = c('Early Stage','Late Stage')))

county.df = county.df %>%
  mutate(outcome_care = In_care_2022,
         outcome_care_factor = factor(outcome_care,levels = c(0,1), labels = c('Not in-care','In-care'))) 

county.df = county.df %>%
  mutate(outcome_TEMP = VL_supp_2022) %>%
  mutate(outcome_vl_supp = case_when(
    outcome_TEMP == 0 ~ 0,
    outcome_TEMP == 1 ~ 1,
    TRUE ~ 0),
    outcome_vl_supp_factor = factor(outcome_vl_supp,levels = c(0,1), labels = c('Unsuppressed','Suppressed')))

################
## Predictors
################

county.df = county.df %>%
  mutate(predictor_education = case_when(
    Education == "<= 8TH GRADE" ~ 0,
    Education == "SOME SCHOOL, LEVEL UNKNOWN" ~ 0,
    Education == "SOME HIGH SCHOOL" ~ 0,
    Education == "HIGH SCHOOL GRAD" ~ 0,
    Education == "SOME COLLEGE" ~ 1,
    Education == "COLLEGE DEGREE" ~ 1,
    Education == "POST-GRADUATE WORK" ~ 1,
    TRUE ~ NA_real_))

county.df = county.df %>%
  mutate(predictor_hispanic = case_when(
    Race == "WHITE" ~ 0,
    Race == "OTHER" ~ 0,
    Race == "BLACK" ~ 0,
    Race == "HISPANIC, ANY RACE" ~ 1,
    TRUE ~ NA_real_))

county.df = county.df %>%
  mutate(predictor_msm = case_when(
    `Exposure Category` == "MSM" ~ 1,
    `Exposure Category` == "IDU" ~ 0,
    `Exposure Category` == "NO REPORTED RISK" ~ 0,
    `Exposure Category` == "MSM & IDU" ~ 1,
    `Exposure Category` == "HETEROSEXUAL CONTACT" ~ 0,
    `Exposure Category` == "OTHER" ~ 0,
    `Exposure Category` == "PERINATAL EXPOSURE" ~ 0,
    TRUE ~ NA_real_))

county.df = county.df %>%
  mutate(predictor_idu = case_when(
    `Exposure Category` == "MSM" ~ 0,
    `Exposure Category` == "IDU" ~ 1,
    `Exposure Category` == "NO REPORTED RISK" ~ 0,
    `Exposure Category` == "MSM & IDU" ~ 1,
    `Exposure Category` == "HETEROSEXUAL CONTACT" ~ 0,
    `Exposure Category` == "OTHER" ~ 0,
    `Exposure Category` == "PERINATAL EXPOSURE" ~ 0,
    TRUE ~ NA_real_))

county.df = county.df %>%
  mutate(predictor_diagnosis_year = `Diagnosis year`)

county.df = county.df %>%
  mutate(predictor_birth_sex = case_when(
    `Birth Sex` == "FEMALE" ~ 0,
    `Birth Sex` == "MALE" ~ 1,
    TRUE ~ NA_real_))

county.df = county.df %>%
  mutate(predictor_zc_per_poverty = zc_poverty / zc_population) %>%
  mutate(predictor_zc_per_hispanic = zc_hispanic / zc_population) %>%
  mutate(predictor_zc_per_education = zc_education / zc_population) %>%
  mutate(predictor_zc_per_race = zc_white / zc_population) %>%
  mutate(predictor_zc_per_employment = zc_employment / zc_population)
    
reg_variable_ind.vec = c(
  "predictor_diagnosis_year",
  "Age.diagnosis",
  "predictor_hispanic",
  "predictor_idu",
  "predictor_msm",
  "predictor_education",
  "predictor_birth_sex",
  "clustered_2022")

reg_variable_zip.vec = c(
  "percent_clustered_2022",
  "zc_income",
  "predictor_zc_per_poverty",
  "predictor_zc_per_hispanic",
  "predictor_zc_per_education",
  "predictor_zc_per_race",
  "predictor_zc_per_employment"
)

reg_variable.vec = c(reg_variable_ind.vec, reg_variable_zip.vec)

################
## Add testing data
################

if (testing_site_bool) {
  
  # county_testing_site.df = read_excel(paste(directory_loc, county_test_file_subloc, sep="")) %>%
  #   rename(zip_code = `Site zip code`) %>%
  #   mutate(across(where(is.character), toupper)) %>%
  #   mutate(zip_code = pad.zip(zip_code),
  #          testing_site_bin = 1) %>%
  #   select(zip_code, testing_site_bin) 
  
  county_testing_site.df = read_excel(paste(directory_loc, county_test_file_subloc, sep="")) %>%
    rename(zip_code = `Site zip code`) %>%
    mutate(across(where(is.character), toupper)) %>%
    mutate(zip_code = pad.zip(zip_code)) %>%
    group_by(zip_code) %>%
    summarize(n.testing.sites.zip = n(),
     testing_site_bin = 1) %>%
    select(zip_code, testing_site_bin,n.testing.sites.zip)
  
  county.df = county.df %>% left_join(county_testing_site.df,
                         by = join_by(rsd_zip_cd == zip_code),
                         relationship = "many-to-one") %>%
    mutate(testing_site_bin = ifelse(is.na(testing_site_bin), 0, testing_site_bin))
  
  reg_variable.vec = c(reg_variable.vec, "testing_site_bin")
}

################
## Table 1
################

county.tbl1 = county.df %>% 
  select(Race.factor, `Birth Sex.factor`, `Exposure Category`, Education,
         clustered_2022,Sequence_ever) %>% # keep only columns of interest
  tbl_summary(     
    # by = outcome,                                               # stratify entire table by outcome
    statistic = list(all_continuous() ~ "{mean} ({sd})",        # stats and format for continuous columns
                     all_categorical() ~ "{n} / {N} ({p}%)"),   # stats and format for categorical columns
    digits = all_continuous() ~ 1,                              # rounding for continuous columns
    type   = all_categorical() ~ "categorical",                 # force all categorical levels to display
    label  = list(                                              # display labels for column names
      Race.factor   ~ "Race",                           
      `Birth Sex.factor` ~ "Sex",
      `Exposure Category` ~ "Transmission Risk",
      Education ~ "Education",
      Sequence_ever ~ 'Sequence available',
      clustered_2022 ~ "Genetic cluster"),
    missing_text = "Missing"                                    # how missing values should display
  )

write_csv(county.tbl1 %>% as.data.frame(), paste0(result_file_loc, "county_tbl1.csv", sep = ""))

outcomes.factor <- c('outcome_diagnosis_factor', 'outcome_care_factor', 'outcome_vl_supp_factor')
outcomes.factor.list <- as.list(outcomes.factor)
names(outcomes.factor.list) <- outcomes.factor

outcome <- outcomes.factor.list[[1]]

list.tab1s <- lapply(outcomes.factor.list,FUN = function(outcome){
  county.tbl1.split = county.df %>% 
    select(Race.factor, `Birth Sex.factor`, `Exposure Category`, Education,
           clustered_2022,Sequence_ever,
           !!outcome) %>% # keep only columns of interest
    tbl_summary(     
      by = !!outcome,                                               # stratify entire table by outcome
      statistic = list(all_continuous() ~ "{mean} ({sd})",        # stats and format for continuous columns
                       all_categorical() ~ "{n} / {N} ({p}%)"),   # stats and format for categorical columns
      digits = all_continuous() ~ 1,                              # rounding for continuous columns
      type   = all_categorical() ~ "categorical",                 # force all categorical levels to display
      label  = list(                                              # display labels for column names
        Race.factor   ~ "Race",                           
        `Birth Sex.factor` ~ "Sex",
        `Exposure Category` ~ "Transmission Risk",
        Education ~ "Education",
        Sequence_ever ~ 'Sequence available',
        clustered_2022 ~ "Genetic cluster"),
        # outcome_diagnosis  ~ "Late-stage Diagnosis",
        # outcome_care  ~ "In Care",
        # outcome_vl_supp  ~ "Viral Suppression"),
      missing_text = "Missing"                                    # how missing values should display
    )
  write_csv(county.tbl1.split %>% as.data.frame(), paste0(result_file_loc, "county_tbl1_",outcome,".csv", sep = ""))
  return(county.tbl1.split %>% as.data.frame())
})

county.tbl1.full <- bind_cols(bind_cols(list.tab1s),county.tbl1 %>% as.data.frame()) %>%
  select(-c("**Characteristic**...4" ,"**Characteristic**...7","**Characteristic**...10" ))

write_csv(county.tbl1.full %>% as.data.frame(), paste0(result_file_loc, "county_tbl1_full.csv", sep = ""))

#can create pseudo dataset and use table strata to create one table as well
# tbl_strata_ex1 <- county.df %>% 
#   select(Race.factor, `Birth Sex.factor`, `Exposure Category`, Education,
#          clustered_2022,Sequence_ever,
#          outcome_diagnosis_factor,outcome_care_factor) %>% # keep only columns of interest
#   tbl_strata(
#     strata = c(outcome_diagnosis_factor,outcome_care_factor),
#     .tbl_fun =
#       ~ .x %>%
#       tbl_summary(     
#         # by = !!outcome,                                               # stratify entire table by outcome
#         statistic = list(all_continuous() ~ "{mean} ({sd})",        # stats and format for continuous columns
#                          all_categorical() ~ "{n} / {N} ({p}%)"),   # stats and format for categorical columns
#         digits = all_continuous() ~ 1,                              # rounding for continuous columns
#         type   = all_categorical() ~ "categorical",                 # force all categorical levels to display
#         label  = list(                                              # display labels for column names
#           Race.factor   ~ "Race",                           
#           `Birth Sex.factor` ~ "Sex",
#           `Exposure Category` ~ "Transmission Risk",
#           Education ~ "Education",
#           Sequence_ever ~ 'Sequence available',
#           clustered_2022 ~ "Genetic cluster"),
#         missing_text = "Missing") %>%
#       add_n(),
#     .header = "**{strata}**, N = {n}"
#     # .header = "**{strata}**"
#   )



################
## Outcome descriptive tables
################


################
## Regression
################

outcome_var_list = c("outcome_diagnosis", "outcome_care", "outcome_vl_supp")
random_effect_var_list = c("rsd_zip_cd", "cur_zip_cd", "cur_zip_cd")

outcome_var_list <- list("diagnosis" = list(outcome = 'outcome_diagnosis',
                              random = 'rsd_zip_cd'),
                         'care' = list(outcome = 'outcome_care',
                              random = 'cur_zip_cd'),
                         'supp' = list(outcome = 'outcome_vl_supp',
                                       random = 'cur_zip_cd'))

var_list <- outcome_var_list[[1]]
regression.output.list <- lapply(X = outcome_var_list,FUN = function(var_list){

  outcome_var_i = var_list$outcome
  print(outcome_var_i)
  
  desc_res.df = county.df %>%
    select(all_of(reg_variable.vec), !! outcome_var_i) %>%
    tbl_summary(by = !! outcome_var_i) %>% as_tibble() %>%
    rename(variable = `**Characteristic**`)
  
  print('univariate')
  uni_reg_res.df = univariate_reg(county.df = county.df,
                                  predictors = reg_variable.vec,
                                  outcome_var = var_list$outcome,
                                  random_effect_var = var_list$random)
  print('lasso tune')
  lambda_tune = Lasso_tune_lambda(county.df = county.df,
                                  predictors = reg_variable.vec,
                                  outcome_var = var_list$outcome,
                                  random_effect_var = var_list$random)
  print('lasso reg')
  multi_reg_res.df = Lasso_reg(county.df = county.df,
                               predictors = reg_variable.vec,
                               outcome_var = var_list$outcome,
                               random_effect_var = var_list$random,
                               lambda_tune = lambda_tune)
  
  reg_res.df = full_join(uni_reg_res.df$summary.table, multi_reg_res.df$summary.table, by = "variable")
  
  outcome_res.df = left_join(desc_res.df, reg_res.df, by = "variable")
  outcome_res.df.round <- outcome_res.df %>%
    mutate(across(.cols = c(estimate_uni, estimate_multi),.fns = function(x){round(x,digits = 2)})) %>%
    mutate(across(.cols = c(p_val_uni,p_val_multi ),.fns = function(x){pvalFormat(x,empty.cell.value = '-')}))
  
  write_csv(outcome_res.df, paste0(result_file_loc, outcome_var_i, "_all_tbl.csv", sep = ""))
  write_csv(outcome_res.df.round, paste0(result_file_loc, outcome_var_i, "_all_tbl_rounded.csv", sep = ""))
  
  return(list(univariate = uni_reg_res.df,
              lambda_tune = lambda_tune,
              multi_reg_res.df = multi_reg_res.df,
              reg_res.df = reg_res.df,
              outcome_res.df = outcome_res.df,
              outcome_res.df.round = outcome_res.df.round))
})


regression.output.list$supp$reg_res.df
regression.output.list$care$reg_res.df
regression.output.list$diagnosis$reg_res.df

################
## Geographic maps
################

outcome_var_list = c("outcome_diagnosis", "outcome_care", "outcome_vl_supp")
outcome_var_list_nice = c("Proportion Late stage dx", "Proportion in-care", "Proportion VL Suppression")
random_effect_var_list = c("rsd_zip_cd", "cur_zip_cd", "cur_zip_cd")

for (i in c(1:length(outcome_var_list))) {
  
  outcome_var_i = outcome_var_list[i]
  
  HIV_geomap = geo_map(title_a = outcome_var_list_nice[i],
                       county.df = county.df,
                       county_zip_list = county_zip_list,
                       outcome_var = outcome_var_list[i],
                       geo_zip_var = random_effect_var_list[i]) 
  
  mapshot(HIV_geomap, file = paste0(result_file_loc, outcome_var_i, "_map.png", sep = ""))
  
}
