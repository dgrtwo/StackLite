# This script cannot be run except by Stack Overflow employees with access to the internal
# sqlstackr package and the Stack Exchange databases.

# It is provided for transparency

library(sqlstackr)
library(dplyr)
library(yaml)
library(tidyr)
library(stringr)
library(lubridate)
library(readr)

# we convert dates to a diff and back because it happens to
# be much faster on large queries with the RSQLServer driver

date_diff <- function(x) as.POSIXct(x, tz = "UTC", origin = "1970-1-1")

query <- "select Id,
            datediff(second, '1970-1-1', CreationDate) as CreationDate,
            datediff(second, '1970-1-1', ClosedDate) as ClosedDate,
            datediff(second, '1970-1-1', DeletionDate) as DeletionDate,
            Tags, Score, OwnerUserId, AnswerCount
        from Posts
        where PostTypeId = 1"

retrieved_time <- with_tz(Sys.time(), "UTC")

questions_raw <- query_StackOverflow(query, collect = TRUE) %>%
  mutate_each(funs(date_diff), CreationDate, ClosedDate, DeletionDate)

# filter only for yesterday, and blank out owner user ID on deleted questions
max_date <- max(as.Date(questions_raw$CreationDate)) - 1

questions <- questions_raw %>%
  filter(as.Date(CreationDate) <= max_date) %>%
  arrange(Id) %>%
  mutate(OwnerUserId = ifelse(is.na(DeletionDate), OwnerUserId, NA))

# write status.yml
s <- list(retrieved_time = as.character(retrieved_time),
          max_date = as.character(max_date),
          number_questions = nrow(questions))
write(as.yaml(s), file = "status.yml")

# turn question tags into one row per question-tag pair
question_tags <- questions %>%
  select(Id, Tags) %>%
  unnest(Tags = str_split(Tags, "\\|")) %>%
  filter(Tags != "") %>%
  rename(Tag = Tags)

questions$Tags <- NULL

# remove existing gz files
unlink("questions.csv.gz")
unlink("question_tags.csv.gz")

write_csv(questions, "questions.csv")
system("gzip questions.csv")

write_csv(question_tags, "question_tags.csv")
system("gzip question_tags.csv")

# knit the README
library(knitr)
knit("README.Rmd")
