# 01_read_and_clean.R
# Read the 2025 national YRBS high school file and build the analysis dataset.
#
# Inputs (download from https://www.cdc.gov/yrbs/data/index.html, 2025 national data):
#   data/XXH2025_YRBS_Data.dat          fixed-width ASCII data file
#   data/2025XXH-SAS-Input-Program.sas  CDC program listing each variable's position
# Output:
#   data/yrbs2025_analysis.rds          recoded variables + survey design variables

library(readr)
library(dplyr)

# ---- Column positions from the CDC SAS input program ----------------------
# Each line looks like "@17 Q1 $1." = starts at character 17, named Q1, 1 wide
sas   <- readLines("data/2025XXH-SAS-Input-Program.sas")
start <- grep("^Input", sas) + 1
end   <- grep("^;", sas)[1] - 1
spec  <- trimws(sas[start:end])

pos   <- as.integer(sub("^@(\\d+).*", "\\1", spec))
name  <- sub("^@\\d+\\s+(\\S+).*", "\\1", spec)
width <- as.integer(sub("^@\\d+\\s+\\S+\\s+\\$?(\\d+).*", "\\1", spec))

# ---- Read the fixed-width file (all as text; codes are categories) ------------
yrbs <- read_fwf("data/XXH2025_YRBS_Data.dat",
                 fwf_positions(pos, pos + width - 1, name),
                 col_types = cols(.default = "c"))
cat("Students:", nrow(yrbs), " Variables:", ncol(yrbs), "\n")

# ---- Recode (code labels from the CDC 2025 formats program) ---------------------
d <- yrbs %>%
  transmute(
    sexually_active = QN57 == "1",                        # sex in the past 3 months
    condom   = ifelse(QN59 == "1", 1, ifelse(QN59 == "2", 0, NA)),
    sex      = factor(Q2, levels = c("1", "2"), labels = c("Female", "Male")),
    grade    = factor(Q3, levels = c("1", "2", "3", "4"),
                      labels = c("9th", "10th", "11th", "12th")),   # ungraded -> NA
    alc_drugs = factor(QN58, levels = c("2", "1"), labels = c("No", "Yes")),
    partners4 = factor(QN56, levels = c("2", "1"), labels = c("Fewer than 4", "4 or more")),
    race = factor(case_when(
      RACEETH == "7"                ~ "White",
      RACEETH == "3"                ~ "Black",
      RACEETH %in% c("4", "8")      ~ "Hispanic/Latino",
      RACEETH == "2"                ~ "Asian",
      RACEETH == "9"                ~ "Multiple (non-Hispanic)",
      RACEETH %in% c("1", "5", "6") ~ "Other"),             # AI/AN, MENA, NH/PI combined
      levels = c("White", "Black", "Hispanic/Latino", "Asian",
                 "Multiple (non-Hispanic)", "Other")),
    identity = factor(case_when(
      Q62 == "1"                ~ "Heterosexual",
      Q62 %in% c("2", "3", "4") ~ "LGB or other",
      Q62 %in% c("5", "6")      ~ "Not sure"),
      levels = c("Heterosexual", "LGB or other", "Not sure")),
    weight  = as.numeric(WEIGHT),
    stratum = STRATUM,
    psu     = PSU
  )

# ---- Missingness among currently sexually active students -------------------------
d_act <- filter(d, sexually_active %in% TRUE)
missing <- data.frame(variable = names(d_act),
                      n_missing = colSums(is.na(d_act)),
                      pct_missing = round(100 * colSums(is.na(d_act)) / nrow(d_act), 1),
                      row.names = NULL)
cat("Currently sexually active:", nrow(d_act), "\n")
print(missing)

dir.create("results", showWarnings = FALSE)
write.csv(missing, "results/missingness_sexually_active.csv", row.names = FALSE)
saveRDS(d, "data/yrbs2025_analysis.rds")
