#' Predict gender from Brazilian first names
#'
#' @description
#' \code{get_gender} uses the IBGE's 2010 Census API to predict gender from Brazilian first names.
#' More specifically, it retrieves data on the number of females and males with the same name
#' in Brazil, or in a given Brazilian state, and calculates the proportion of females using it.
#' The function classifies a name as male or female only when that proportion is higher than
#' a given threshold (e.g., \code{female if proportion > 0.9}, or \code{male if proportion < 0.1});
#' proportions below this threshold are classified as missing (\code{NA}).
#'
#' Multiple names can be passed to the function call. To speed the calculation process,
#' the package aggregates equal first names to make fewer requests to the IBGE's API.
#'
#' @param names A string specifying a person's first name. Names can also be passed to the function
#' as a full name (e.g., Ana Maria de Souza). \code{get_gender} is case insensitive.
#' @param state A string with the state of federation abbreviation (e.g., \code{RJ} for Rio de Janeiro).
#' @param prob Report the proportion of female uses of the name? Defaults to \code{FALSE}.
#' @param threshold Numeric indicating the threshold used in predictions. Defaults to 0.9.
#'
#' @details Information on the Brazilian first names uses by gender was collect in the 2010 Census
#' (Censo Demografico de 2010, in Portuguese), in July of that year, by the Instituto Brasileiro de Demografia
#' e Estatistica (IBGE). The surveyed population includes 190,8 million Brazilians living in all 27 states.
#' According to the IBGE, there are more than 130,000 unique first names in this population.
#'
#' @note Names with different spell (e.g., Ana and Anna, or Marcos and Markos) are considered different names.
#' Additionally, only names with more than 20 occurrences, or more than 15 occurrences in a given state,
#' are considered by the IBGE's API.
#'
#' @references For more information on the IBGE's data, please check (in Portuguese):
#' \url{http://censo2010.ibge.gov.br/nomes/}
#'
#' @seealso \code{\link{map_gender}}
#'
#' @return \code{get_gender} may returns three different values: \code{Female}, if the name provided is female;
#' \code{Male}, if the name provided is male; or \code{NA}, if we can not predict gender from the name given the chosen threshold.
#'
#' If the \code{prob} argument is set to \code{TRUE}, then the function returns the proportion of females uses of the provided name.
#'
#' @examples
#' \donttest{
#' # Use get_gender to predict the gender
#' # of a person based on her/his first name
#' get_gender('mario')
#' get_gender('Maria da Silva Santos')
#' get_gender('MARIA DA SILVA SANTOS')
#'
#' # It is possible to filter results by state
#' get_gender('ana', state = 'sp')
#'
#' # To change the employed threshold
#' get_gender('ariel', threshold = '0.8')
#'
#' # Or to get the proportion of females
#' # with the name provided
#' get_gender('iris', prob = TRUE)
#'
#' # Multiple names can be predict at the same time
#' get_gender(c('joao', 'ana', 'benedita', 'rafael'))
#'
#' # In different states
#' get(rep('cris', 3), c('sp', 'am', 'rs'))
#' }
#'
#' @import dplyr
#' @import httr
#' @export

get_gender <- function(names, state = NULL, prob = FALSE, threshold = 0.9){


  # Names
  names <- clean_names(names)
  un_names <- unique(names)
  ln_un <- length(un_names)
  ln <- length(names)

  # Set pauses
  if(ln > 4) pause <- TRUE
  else pause <- FALSE

  # Whole country & unique names
  if(is.null(state) & ln == ln_un){

    # Return
    out <- sapply(1:ln, function(i) get_gender_api(names[i], state, prob = prob, threshold = threshold, pause = pause))
    return(out)
  }

  # Whole country & non-unique names
  if(is.null(state)) {

    # Pick unique names
    gender_pred <- sapply(1:ln_un, function(i) get_gender_api(un_names[i], state, prob = prob, threshold = threshold, pause = pause))

    # Join
    names <- dplyr::tibble(names = names)
    un_names <- dplyr::tibble(names = un_names, prob = gender_pred)

    # Return
    out <- dplyr::left_join(names, un_names, by = c("names"))$prob
    return(out)
  }

  # By state & unique names
  if(ln == ln_un){

    # Return
    state <- get_state(state, ln)
    out <- sapply(1:ln, function(i) get_gender_api(names[i], state[i], prob = prob, threshold = threshold, pause = pause))
    return(out)
  }

  # By state & non-unique names
  state <- get_state(state, ln)
  names <- dplyr::tibble(names = names, state = state)
  dis_names <- dplyr::distinct(names)

  dis_names$prob <- sapply(1:length(dis_names$names), function(i) get_gender_api(dis_names$names[i], dis_names$state[i], prob = prob, threshold = threshold, pause = pause))
  out <- dplyr::left_join(names, dis_names, by = c("names", "state"))$prob

  return(out)
}


# Get individual results from API
get_gender_api <- function(name, state, prob, threshold, pause = pause){


  # API endpoint
  ibge <- "http://servicodados.ibge.gov.br/api/v1/censos/nomes/basica"

  # GET
  females <- httr::GET(ibge, query = list(nome = name, regiao = state, sexo = "f"))
  if(pause) Sys.sleep(sample(seq(1, 10, by = 0.1), 1))
  males <- httr::GET(ibge, query = list(nome = name, regiao = state, sexo = "m"))

  # Test responses
  res <- test_responses(females, males, prob)
  if(!is.null(res)) return(res)

  # Parse freq
  females <- httr::content(females, as = "parsed")[[1]]$freq
  males <- httr::content(males, as = "parsed")[[1]]$freq

  # Return
  fprob <- females / sum(females, males)
  if(prob) return(fprob)
  round_guess(fprob, threshold)
}

