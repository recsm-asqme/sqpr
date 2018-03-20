#' Extract variable estimates from the SQP prediction algorithm
#'
#' @param id a numeric vector containing the id(s) of variable(s) of interest. Can
#' be one or more id's.
#' @param all_columns a logical stating whether to extract all available
#' columns from the SQP database. See the details section for a list of all possible variables.
#'
#' @details
#' SQP predictions can have both 'authorized' predictions, which are
#' performed by the SQP software and 'crowd-sourced' predictions which are
#' added to the database by other users. By default, \code{get_estimates}
#' always returns the 'authorized' prediction when it is available. When
#' it is not, it returns the first non-authorized prediction, and so on.
#' If neither 'authorized' nor 'crowd-sourced' predictions are available it raises
#' an error.
#'
#' \code{get_estimates} returns a four column \code{\link[tibble]{tibble}} with
#' the question name and the estimates for \code{quality}, \code{reliability} and
#' \code{validity}. However, if \code{all_columns} is set to \code{TRUE} the returned
#' \code{\link[tibble]{tibble}} contains new columns. Below you can find the description
#' of all columns:
#'
#' \itemize{
#' \item question: the literal name of the question in the questionnaire of the study
#' \item question_id: the API internal ID of the question
#' \item id: this is the coding ID, that is, the coding of the authorized prediction
#' \item created: Date of the API request
#' \item routing_id: Version of the coding scheme applied to get that prediction.
#' \item authorized: Whether it is an 'authorized' prediction or not. See the details section
#' \item complete: Whether all fields of the coding are complete
#' \item error: Whether there was an error in making the prediction. For an example,
#'  see \link{http://sqp.upf.edu/loadui/#questionPrediction/12552/42383}
#' \item errorMessage: The error message, if there was an error
#' \item reliability: The strenght between the true score factor and the observed
#'  variable or 1 - proportion random error in the observed variance. Computed as
#'  the squared of the reliability coefficient
#' \item validity: The strength between the latent concept factor and the
#'  true score factor or 1 - proportion method error variance in the true
#'  score variance. Computed as the squared of the validity coefficient
#' \item quality: The strength between the latent concept factor and the
#'  observed variable or 1 - proportion of random and method error variance
#'  in the latent concept's variance. Computed as the product of reliability
#'   and validity.
#' \item reliabilityCoefficient: The effect between the true score factor and
#'  the observed variable
#' \item validityCoefficient: The effect between the latent concept factor and
#'  the true score factor
#' \item methodEffectCoefficient: The effect between the method factor and the
#'  true score factor
#' \item qualityCoefficient: It is computed as the squared root of the quality
#' \item reliabilityCoefficientInterquartileRange: Interquartile range for the reliability coefficient
#' \item validityCoefficientInterquartileRange: Interquartile range for the validity coefficient
#' \item qualityCoefficientInterquartileRange: Interquartile range for the quality coefficient
#' \item reliabilityCoefficientStdError: Predicted standard error of the reliability coefficient
#' \item validityCoefficientStdError: Predicted standard error of the validity coefficient
#' \item qualityCoefficientStdError: Predicted standard error of the quality coefficient
#' }
#'
#'
#' @seealso \code{\link{sqp_login}} for loging in to the SQP API through R and
#' \code{\link{find_questions}} and \code{\link{find_studies}} for locating
#' the variables of interest to use in \code{get_estimates}.
#'
#' @return \code{get_estimates} returns a \code{\link[tibble]{tibble}} with the predictions.
#' The number of columns depends on the \code{all_columns} argument.
#' \code{get_question_name} returns a character vector with the question name(s).
#' @export
#'
#' @examples
#'
#' \dontrun{
#'
#' # Log in with sqp_login first. See ?sqp_login
#'
#' get_estimates(c(1, 2, 86))
#'
#' get_estimates(c(1, 2, 86), all_columns = TRUE)
#'
#' # Explore variable names
#'
#' get_question_name(1)
#'
#' get_question_name(1:10)
#'
#' }
#'
get_estimates <- function(id, all_columns = FALSE) {
  stopifnot(is.numeric(id), length(id) >= 1)

  collapsed_id <- paste0(id, collapse = ",")
  url_id <- paste0(sqp_env$questions, collapsed_id, sqp_env$q_estimates)

  q_name <- get_question_name(id)
  raw_data <- object_request(url_id, estimates = TRUE)

  list_data <- purrr::pmap(list(raw_data, q_name, id),
                           make_estimate_df,
                           all_columns = all_columns)

  final_df <- tibble::as_tibble(do.call(rbind, list_data))

  final_df <- sqp_reconstruct(final_df)
  final_df
}

#' @rdname get_estimates
#' @export
get_question_name <- function(id) {
  stopifnot(is.numeric(id), length(id) >= 1)

  collapsed_id <- paste0(id, collapse = ",")
  almost_q_name <-
    httr::content(
      safe_GET(paste0(sqp_env$questions, collapsed_id)), as = "text"
    )

  q_name <- tolower(jsonlite::fromJSON(almost_q_name)$short_name)
}

make_estimate_df <- function(raw_data, var_name, id, all_columns = FALSE) {

  # If empty estimates..
  if (all(c(1, 1) == dim(raw_data))) {
    sqp_data <-
      sqp_construct_(var_name,
                     metrics = list(quality = NA_integer_), # random metric
                     all_columns)
    # only for all columns, bc otherwise
    # you the 4 column layout of sqp of
    # short columns is lost
    if (all_columns) sqp_data$question_id <- id

    return(sqp_data)
  }

  valid_rows <- !is.na(raw_data$authorized)

  if (!any(valid_rows)) stop("No valid predictions for", " `", var_name,"`")

  raw_data <- raw_data[valid_rows, ]

  # If two authorized predictions
  # are added, always returns the first one
  # in order
  row_to_pick <- ifelse(any(raw_data$authorized),
                        which(raw_data$authorized), 1)

  cols_to_pick <- if (all_columns) names(raw_data) else sqp_env$short_estimate_variables
  final_df <- raw_data[row_to_pick, cols_to_pick]

  final_df <- purrr::set_names(final_df, ~ gsub("prediction.", "", .x))

  final_df <- tibble::add_column(final_df, question = var_name, .before = 1)
  final_df
}