
###'######################################################################
###'
###' Model Estimation
###' 
###' (1) Prediction models for the per-pupil expenditures/revenues
###' 
###'     => first-stage model of IV
###'     
###'     
###' Replicate/evaluate the Johnson & Tanner's research design
###' 
###' (1) Event study (interrupted time series)
###' 
###' 
###' (2) A simulated instrumental variable approach 
###'     using the LCFF funding formula
###' 
###' 
###' 20180813 JoonHo Lee
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
data_dir <- c("D:/Data/LCFF")


### Call libraries
library(tidyverse)
library(car)
library(plm)
library(lme4)
library(sjPlot)


### Call functions
list.files("functions", full.names = TRUE) %>% walk(source)



###'######################################################################
###'
###' Import pre-cleaned datasets
###'
###'

### Per-pupil expenditures & revenues
load(file = "processed_data/list_expenditures_def_1_2.RData")
load(file = "processed_data/list_revenues.rda")


### LCFF funding snapshot data: FY13-14, 14-15, 15-16
load(file = "processed_data/funding_snapshot_3year.RData")


### The State of California's overall and local revenues/expenditures data
state_df <- read.csv(file = "processed_data/May_Revision_Budget_2000_to_2016.csv")



###'######################################################################
###'
###' Construct the simulated instrumental variable (Z_{d})
###' 
###' (1) Per-pupil supplemental grant: Supp_{d} = Base_{d} * 0.2 * UPP
###' 
###' (2) Per-pupil concentration grant: Conc_{d} = Base_{d} * max[UPP - 0.55, 0]
###' 
###' (3) Simulated instrumental variable: SimIV_{d} = Supp_{d} + Conc_{d} 
###' 
###' => The state's allocation of Supplemental and Concentration Grants is
###'    the focal point of our use of the funding formula 
###'    to isolate exogenous changes in district-level revenue 
###'    caused by the state policy change
###'
###' (4) Formula weight: 0.20 * UPP + max[UPP - 0.55, 0]
###'
###'
###' *** The meaning of the simulated IV
###' => The reform-induced changes in district spending
###' => Supplemental and concentration grant
###' 
###' Importantly, these reform-induced changes in district spending, 
###' which are credibly identified from the funding formula 
###' (and which serve as the instrumental variables), 
###' are unrelated to changes in child family and neighborhood characteristics 
###' conditional on the baseline level of disadvantage in each district.
###' (After controlling for UPP => Conditional exogeneity)
###'
###'

### Remove charter school entries
df <- fund1314 %>%
  filter(LEA_type == "School District")


### Generate simulated IV and formula weight
df <- df %>%
  mutate(formula_weight = 0.2 * Unduplicated + 
           ifelse(Unduplicated > 0.55, 0.5 * (Unduplicated - 0.55), 0), 
         SimSupp = Base * 0.2 * Unduplicated, 
         SimConc = ifelse(Unduplicated > 0.55, 0.5 * Base * (Unduplicated - 0.55), 0),
         SimIV = SimSupp + SimConc, 
         Supp_Conc = Supplemental + Concentration) %>%
  select(CountyCode, DistrictCode, LEA, Total_ADA, Unduplicated, formula_weight,  
         Base, Supplemental, SimSupp, Concentration, SimConc, Supp_Conc, SimIV, 
         everything())


### Round the simulated values for the visual comparison
cols_to_round <- which(names(df) %in% c("Base", "SimSupp", "SimConc", "SimIV"))

df <- df %>% 
  mutate_at(cols_to_round, round, 0)


### Are the simulated values consistent with the provided values?
df_nonzeroBase <- df %>% 
  filter(Base != 0)

all.equal(df_nonzeroBase$SimSupp, df_nonzeroBase$Supplemental)
all.equal(df_nonzeroBase$SimConc, df_nonzeroBase$Concentration)
all.equal(df_nonzeroBase$SimIV, df_nonzeroBase$Supp_Conc)


### Check the distribution of funding formula weights
ggplot(df, aes(formula_weight)) +
  geom_density()


### Generate decile dummies for simulated IV

df <- df %>%
  mutate(decile = ntile(SimIV, 10))

table(df$decile)



###'######################################################################
###'
###' Merge FY1314 funding snapshot to per-pupil expenditure panel data
###' 
###' 

### Extract dataframe
assign(names(list_expenditures_def_1)[[1]], list_expenditures_def_1[[1]])


### Rename CountyCode and DistrictCode and convert them to numeric
df <- df %>%
  mutate(Ccode = as.numeric(CountyCode), 
         Dcode = as.numeric(DistrictCode)) %>%
  select(Ccode, Dcode, everything()) %>%
  select(-(CountyCode:DistrictCode))


### Merge the two datasets
total_exp <- left_join(total_exp, df, by = c("Ccode", "Dcode"))


### Log transformation of outcome variables
total_exp <- total_exp %>%
  mutate(log_y = if_else(sum_value_PP_16 == 0, 0, log(sum_value_PP_16)))



###'######################################################################
###'
###' Fitting piecewise growth curve models:
###' 
###' => Provide visual evidence that the funding formula weight 
###' 
###'    does not predict changes in funding levels in the previous years
###' 
###'    leading up to the LCFF policy change in 2013
###'
###' Level 1: 
###' Y_{ij} = beta_{0j} + beta_{1j} time_1 + beta_{2j} time_2 + r_{ij}
###'
###' Level 2:
###' beta_{0j} = gamma_{00} + gamma_{01} formula_weight_{j} + U_{0j}
###' beta_{1j} = gamma_{10} + gamma_{11} formula_weight_{j} + U_{1j}
###' beta_{2j} = gamma_{20} + gamma_{21} formula_weight_{j} + U_{2j}
###'
###' Time coding scheme:
###' time_1: the pre-recession housing bubble (2003-2006) 
###' time_2: the housing crash and ensuing recession (2007-2009 + 2009-2012)
###' time_3: LCFF years (2013-2016)
###'
###' time_1: c(0, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3)
###' time_2: c(0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 6, 6, 6, 6)
###' time_3: c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4)
###'
###'

### Initial exploratory plot
df_plot <- total_exp %>%
  filter(Dtype %in% c("ELEMENTARY", "HIGH", "UNIFIED"))
  
p <- ggplot(aes(x = Fiscalyear, y = log_y), data = df_plot) +
  geom_line(aes(group = Dcode), color = "gray") + 
  geom_smooth(aes(group = 1), size = 3, color = "red", se = FALSE) +
  facet_grid(.~ Dtype) + 
  theme_trend + 
  scale_x_continuous(breaks = seq(min(df_plot$Fiscalyear), 
                                  max(df_plot$Fiscalyear), 
                                  by = 1))

ggsave("figures/total_exp_growth.pdf", p, width = 15, height = 8)


### Generate time variables for piecewise regression
Fiscalyear <- 2003:2016
time_1 <- c(0, 1, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3)
time_2 <- c(0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 6, 6, 6, 6)
time_3 <- c(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4)
time_df <- data.frame(Fiscalyear, time_1, time_2, time_3)

total_exp <- left_join(total_exp, time_df, by = c("Fiscalyear")) 


### Fit the piecewise growth curve model

fit_piece <- lmer(log_y ~ (time_1 + time_2 + time_3) * formula_weight + 
                    (time_1 + time_2 + time_3 | Dcode), 
                  data = total_exp, REML = FALSE)

summary(fit_piece)


### Graph fitted curves

FittedFE <- function(x) model.matrix(x) %*% fixef(x)

df_plot_fit <- data.frame(fit_piece@frame, fitted = FittedFE(fit_piece))

df_plot_fit <- df_plot_fit %>% arrange(Dcode)

df_plot_fit <- left_join(df_plot_fit, time_df, by = c("time_1", "time_2", "time_3"))

p <- ggplot(df_plot_fit, aes(x = Fiscalyear, y = log_y)) + 
  # geom_point(shape = 19) +
  stat_summary(fun.y = mean, geom = "point", size = 5, shape = 1) + 
  geom_line(aes(y = fitted), lwd = 1.5)



###'######################################################################
###'
###' Per-pupil revenue prediction model
###' 
###' - Restrict the analysis to the per-pupil revenue only from state
###'
###'

###' Outcome variable
###' per-pupil revenue from state across years 2003-2016
names(list_revenues)
df_rev <- list_revenues[["revenue_by_object"]]

table(df_rev$revenue_by_object)
df_rev <- df_rev %>%
  filter(revenue_by_object %in% c("Revenue Limit (LCFF from 2013)", 
                                  "Other State Revenue"))


### Total state-level ADA across years 2003-2016
state_ADA <- total_exp %>%
  group_by(Fiscalyear) %>%
  summarise(stateADA = sum(K12ADA_C, na.rm = TRUE)) %>%
  filter(!is.na(Fiscalyear))

plot_trend_xy(state_ADA, x = Fiscalyear, y = stateADA, yline = 2013, 
              ylim = c(5000000, 6000000))
  

###' Generate the two state-level predictors
###' (1) CAExp: the total non K-12 state expenditures per pupil for birth cohort
###' (2) CALocalAssist: the state local assistance provided (excluding education)

state_operations_df <- state_df %>%
  filter(Category_1 == "State Operations") %>%
  filter(!(Category_2 %in% c("Education"))) %>%
  group_by(Fiscalyear) %>%
  summarise(CAExp = sum(value_16, na.rm = TRUE)) %>%
  left_join(state_ADA, by = c("Fiscalyear")) %>%
  mutate(CAExp_PP = CAExp/stateADA) %>%
  filter(!is.na(CAExp_PP))


local_assistance_df <- state_df %>%
  filter(Category_1 == "Local Assistance") %>%
  filter(!(Category_2 %in% c("Public Schools - K-12"))) %>%
  group_by(Fiscalyear) %>%
  summarise(CALocalAssist = sum(value_16, na.rm = TRUE)) %>%
  left_join(state_ADA, by = c("Fiscalyear")) %>%
  mutate(CALocalAssist_PP = CALocalAssist/stateADA) %>%
  filter(!is.na(CALocalAssist_PP))


state_predictors <- state_operations_df %>%
  select(-stateADA) %>% 
  left_join(local_assistance_df, by = c("Fiscalyear"))


plot_trend_xy(state_predictors, x = Fiscalyear, y = CAExp_PP, 
              yline = 2013, ylim = c(1, 5))
plot_trend_xy(state_predictors, x = Fiscalyear, y = CAExp, 
              yline = 2013, ylim = c(15000000, 26000000))
plot_trend_xy(state_predictors, x = Fiscalyear, y = CALocalAssist_PP, 
              yline = 2013, ylim = c(5, 10))
plot_trend_xy(state_predictors, x = Fiscalyear, y = CALocalAssist, 
              yline = 2013, ylim = c(30000000, 50000000))


### Group sum per-pupil revenues
df_rev_sum <- df_rev %>% 
  group_by(Fiscalyear, Ccode, Dcode) %>%
  summarise(sum_value_PP_16 = sum(sum_value_PP_16, na.rm = TRUE))


### Merge predictors to dataset with outcome variable
df_rev_pred <- df_rev_sum %>%
  left_join(state_predictors, by = c("Fiscalyear")) %>%
  left_join(df, by = c("Ccode", "Dcode")) %>%
  mutate(timetrend = Fiscalyear - 2003)


###' Fit the regression model to estimate the counterfactual district revenue
###' from state if LCFF had not occurred
###' 
###' (1) Run only for 2003-2012, just prior to LCFF, get coefficients
###' (2) Predict the level of district per-pupil revenues from state sources
###'     for all years in the data, including the post-LCFF era (2013-2016)

df_pre <- df_rev_pred %>%
  filter(!(Fiscalyear %in% c(2013, 2014, 2015, 2016))) %>%
  select(Fiscalyear, Ccode, Dcode, sum_value_PP_16, CAExp_PP, CALocalAssist_PP, 
         timetrend, formula_weight) %>% 
  rename(state_rev_PP_16 = sum_value_PP_16)

valid_Dcode <- unique(df_pre$Dcode[complete.cases(df_pre)])

df_pre <- df_pre %>%
  filter(Dcode %in% valid_Dcode)

fit_preLCFF <- lm(state_rev_PP_16 ~ CAExp_PP + CALocalAssist_PP + 
                  timetrend*formula_weight + factor(Dcode), data = df_pre)

df_prepost <- df_rev_pred %>%
  select(Fiscalyear, Ccode, Dcode, sum_value_PP_16, 
         CAExp_PP, CALocalAssist_PP, timetrend, formula_weight) %>%
  rename(state_rev_PP_16 = sum_value_PP_16) %>%
  filter(Dcode %in% valid_Dcode)

df_prepost$state_rev_PP_16_pred <- predict(fit_preLCFF, df_prepost)

df_prepost$Fiscalyear <- df_prepost$timetrend + 2003

df_actual_pred <- df_prepost %>%
  group_by(Fiscalyear) %>%
  summarise(actual_revenue = mean(state_rev_PP_16, na.rm = TRUE), 
            predicted_revenue = mean(state_rev_PP_16_pred, na.rm = TRUE)) %>%
  gather(actual_vs_pred, mean_rev_PP_16, 2:3)

plot_trend_grp(df_actual_pred, Fiscalyear, mean_rev_PP_16, actual_vs_pred, 
               yline = 2013, ylim = c(7500, 15000))



###'######################################################################
###'
###' Replicate Figure 10: Using actual vs. predicted per-pupil revenue difference
###' 
###' - The evolution of district per-pupil revenue "from the state" 
###' 
###'   before and after LCFF
###'
###'   according to the formula weight
###'
###'

names(df_prepost)

###' Merge two additional information:
###' (1) K12ADA_C: to get weighted means of the differences
###' (2) SimIV and Sim_IV based grouping variables

df_SimIV <- df %>%
  select(Ccode, Dcode, SimIV, decile) %>%
  mutate(quartile = ntile(SimIV, 4), 
         quintile = ntile(SimIV, 5))

df_K12ADA <- total_exp %>%
  select(Fiscalyear, Ccode, Dcode, K12ADA_C)

df_prepost <- df_prepost %>% 
  left_join(df_K12ADA, by = c("Fiscalyear", "Ccode", "Dcode")) %>%
  left_join(df_SimIV, by = c("Ccode", "Dcode"))


### Plot 

sapply(df_prepost_plot, class)

df_prepost$quartile <- factor(df_prepost$quartile)

df_prepost_plot <- df_prepost %>% 
  mutate(pred_diff = state_rev_PP_16 - state_rev_PP_16_pred) %>% 
  group_by(Fiscalyear, quartile) %>%
  summarise(pred_diff_median = round(median(pred_diff, na.rm = TRUE), 0)) %>%
  arrange(quartile, Fiscalyear)


plot_trend_grp(df_prepost_plot, Fiscalyear, pred_diff_median, quartile, 
               yline = 2013) + geom_hline(yintercept = 0)


### Do it this with regression model!
df_prepost$Fiscalyear <- factor(df_prepost$Fiscalyear)
df_prepost$decile <- factor(df_prepost$decile)
df_prepost$Fiscalyear <- relevel(df_prepost$Fiscalyear, "2013")

df_prepost <- mutate(df_prepost, pred_diff = state_rev_PP_16 - state_rev_PP_16_pred)


fit1 <- lm(state_rev_PP_16 ~ state_rev_PP_16_pred, 
           data = df_prepost)


fit2 <- lm(state_rev_PP_16 ~ state_rev_PP_16_pred + Fiscalyear, 
           data = df_prepost)

coef2 <- data.frame(fit2$coefficients)

write.csv(coef2, file = "tables/coef2.csv")


fit3 <- lm(pred_diff ~ Fiscalyear, 
           data = df_prepost)

coef3 <- data.frame(fit3$coefficients)  

write.csv(coef3, file = "tables/coef3.csv")


fit4 <- lm(state_rev_PP_16 ~ state_rev_PP_16_pred + Fiscalyear + factor(Dcode), 
           data = df_prepost)

coef4 <- data.frame(fit4$coefficients)  

write.csv(coef4, file = "tables/coef4.csv")





###'######################################################################
###'
###' The first stage model predicting average per-pupil spending
###' 
###' in district "d" in year "t"
###' 
###' - (1) event time dummies
###' - (2) formula weight dummies Q_{2013}  
###' 
###' => The coefficients for the two-way interactions map out
###'    the dynamic treatment effects of the LCFF reform on per-pupil spending
###'    for districts in spending quantile Q_{2013}
###' 
###' - (3) district fixed-effect
###'
###'

### Merge predicted revenues
df <- total_exp
df_prepost_merge <- df_prepost %>%
  select(Fiscalyear, Dcode, total_rev_PP_16, total_rev_PP_16_pred)

df <- df %>%
  left_join(df_prepost_merge, by = c("Fiscalyear", "Dcode"))


### Convert to factors and set reference category
df$Fiscalyear <- factor(df$Fiscalyear)
df$decile <- factor(df$decile)
df$Fiscalyear <- relevel(df$Fiscalyear, "2013")


### Tidy up analytical sample
df <- df %>%
  filter(Dtype %in% c("ELEMENTARY", "HIGH", "UNIFIED")) %>%
  select(log_y, decile, Fiscalyear, Dcode, total_rev_PP_16_pred) 


### Filter only valid district
df <- df %>%
  filter(Dcode %in% valid_Dcode)


### Fixed effects using least squares dummy variable model
df$Fiscalyear <- factor(df$Fiscalyear)
df$decile <- factor(df$decile)
df$Fiscalyear <- relevel(df$Fiscalyear, "2013")

mm <- model.matrix(~ decile*Fiscalyear, df)
write.csv(mm, file = "tables/model_matrix.csv")

fit_lm <-lm(log_y ~ mm + total_rev_PP_16_pred + factor(Dcode), data = df)
summary(fit_lm)


### Plot dynamic treatment effects

coef <- data.frame(fit_lm$coefficients)

coef$coef <- rownames(coef)

rownames(coef) <- NULL

coef_int <- coef[grepl(":", coef$coef), ]

coef_int <- coef_int %>%
  separate(coef, c("decile", "year"), ":") %>%
  select(decile, year, fit_lm.coefficients) %>%
  rename(coef = fit_lm.coefficients) %>% 
  arrange(decile, year)
  
coef_int$year <- as.numeric(substr(coef_int$year, 11, 14))


coef_int$decile <- factor(gsub('\\D+','', coef_int$decile), 
                          levels = rev(as.character(2:10)))
coef_int$coef <- round(coef_int$coef, 2)


coef_2013 <- data.frame(decile = as.character(2:10), 
                        year = rep(2013, 9), 
                        coef = rep(0, 9))

coef_int <- coef_int %>%
  bind_rows(coef_2013) %>%
  arrange(decile, year)


p1 <- plot_trend_grp(coef_int, year, coef, decile, yline = 2013, 
                     ylim = auto_ylim(coef_int$coef))

labels <- labs(title = "Effects of LCFF funding formula on per-pupil expenditure",
               subtitle = "Definition 1, Inflation-adjusted by CPI-U deflator", 
               x = "Fiscal Year",  
               y = "Difference in district per-pupil expenditures compared to 2013 & Decile 1") 

p1 <- p1 + labels

p1





