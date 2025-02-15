;; -*-scheme-*- ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; portfolio.scm
;; by Robert Merkel (rgmerk@mira.net)
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 2 of
;; the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, contact:
;;
;; Free Software Foundation           Voice:  +1-617-542-5942
;; 51 Franklin Street, Fifth Floor    Fax:    +1-617-542-2652
;; Boston, MA  02110-1301,  USA       gnu@gnu.org
;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (gnucash reports standard portfolio))

(use-modules (gnucash engine))
(use-modules (gnucash utilities))
(use-modules (gnucash core-utils))
(use-modules (gnucash app-utils))
(use-modules (gnucash report))
(use-modules (srfi srfi-1))

(define reportname (N_ "Investment Portfolio"))

(define optname-price-source (N_ "Price Source"))
(define optname-shares-digits (N_ "Share decimal places"))
(define optname-zero-shares (N_ "Include accounts with no shares"))

(define (options-generator)
  (let* ((options (gnc-new-optiondb)))

    ;; General Tab
    ;; date at which to report balance
    (gnc:options-add-report-date!
     options gnc:pagename-general
     (N_ "Date") "a")

    (gnc:options-add-currency!
     options gnc:pagename-general (N_ "Report's currency") "c")

    (gnc:options-add-price-source!
     options gnc:pagename-general
     optname-price-source "d" 'pricedb-latest)

    (gnc-register-number-range-option options
      gnc:pagename-general optname-shares-digits
      "e" (N_ "The number of decimal places to use for share numbers.") 2
      0 9 1)

    ;; Account tab
    (gnc-register-account-list-limited-option options
      gnc:pagename-accounts (N_ "Accounts")
      "b"
      (N_ "Stock Accounts to report on.")
      (gnc:filter-accountlist-type
       (list ACCT-TYPE-STOCK ACCT-TYPE-MUTUAL)
       (gnc-account-get-descendants-sorted (gnc-get-current-root-account)))
      (list ACCT-TYPE-ASSET ACCT-TYPE-STOCK ACCT-TYPE-MUTUAL))

    (gnc-register-simple-boolean-option options
      gnc:pagename-accounts optname-zero-shares "e"
      (N_ "Include accounts that have a zero share balances.")
      #f)

    (gnc:options-set-default-section options gnc:pagename-general)
    options))

;; This is the rendering function. It accepts a database of options
;; and generates an object of type <html-document>.  See the file
;; report-html.txt for documentation; the file report-html.scm
;; includes all the relevant Scheme code. The option database passed
;; to the function is one created by the options-generator function
;; defined above.
(define (portfolio-renderer report-obj)

 (let ((work-done 0)
       (work-to-do 0))

  ;; These are some helper functions for looking up option values.

  (define (get-option section name)
    (gnc-optiondb-lookup-value  (gnc:report-options report-obj) section name))

  (define (table-add-stock-rows table accounts to-date currency
                                exchange-fn price-fn include-empty collector)

   (let ((share-print-info
	  (gnc-share-print-info-places
	   (inexact->exact (get-option gnc:pagename-general
				       optname-shares-digits)))))

    (define (table-add-stock-rows-internal accounts odd-row?)
      (if (null? accounts) collector
          (let* ((row-style (if odd-row? "normal-row" "alternate-row"))
                 (current (car accounts))
                 (rest (cdr accounts))
                 (commodity (xaccAccountGetCommodity current))
                 (ticker-symbol (gnc-commodity-get-mnemonic commodity))
                 (listing (gnc-commodity-get-namespace commodity))
                 (unit-collector (gnc:account-get-comm-balance-at-date
                                  current to-date #f))
                 (units (cadr (unit-collector 'getpair commodity #f)))

                 (price-info (price-fn commodity to-date))
                 (price (car price-info))
                 (price-monetary (if price
                                     (gnc:make-gnc-monetary
                                      (gnc-price-get-currency price)
                                      (gnc-price-get-value price))
                                     (gnc:make-gnc-monetary
                                      currency
                                      (cdr price-info))))
                 (value (exchange-fn (gnc:make-gnc-monetary commodity units)
                                     currency)))

	    (set! work-done (+ 1 work-done))
	    (gnc:report-percent-done (* 100 (/ work-done work-to-do)))
	    (if (or include-empty (not (gnc-numeric-zero-p units)))
		(begin (collector 'add currency (gnc:gnc-monetary-amount value))
		       (gnc:html-table-append-row/markup!
			table
			row-style
			(list (gnc:html-account-anchor current)
			      (gnc:make-html-table-header-cell/markup "text-cell" ticker-symbol)
			      (gnc:make-html-table-header-cell/markup "text-cell" listing)
			      (gnc:make-html-table-header-cell/markup
			       "number-cell"
			       (xaccPrintAmount units share-print-info))
			      (gnc:make-html-table-header-cell/markup
			       "number-cell"
                               (gnc:html-price-anchor price price-monetary))
			      (gnc:make-html-table-header-cell/markup
			       "number-cell" value)))
		       ;;(display (format #f "Shares: ~6d  " (gnc-numeric-to-double units)))
		       ;;(display units) (newline)
		       (if price (gnc-price-unref price))
		       (table-add-stock-rows-internal rest (not odd-row?)))
		(begin (if price (gnc-price-unref price))
		       (table-add-stock-rows-internal rest odd-row?))))))

    (set! work-to-do (length accounts))
    (table-add-stock-rows-internal accounts #t)))

  ;; Tell the user that we're starting.
  (gnc:report-starting reportname)

  ;; The first thing we do is make local variables for all the specific
  ;; options in the set of options given to the function. This set will
  ;; be generated by the options generator above.
  (let ((to-date     (gnc:time64-end-day-time
                      (gnc:date-option-absolute-time
                       (get-option gnc:pagename-general "Date"))))
        (accounts    (get-option gnc:pagename-accounts "Accounts"))
        (currency    (get-option gnc:pagename-general "Report's currency"))
        (report-title (get-option gnc:pagename-general
                                  gnc:optname-reportname))
        (price-source (get-option gnc:pagename-general
                                  optname-price-source))
        (include-empty (get-option gnc:pagename-accounts
                                  optname-zero-shares))

        (collector   (gnc:make-commodity-collector))
        ;; document will be the HTML document that we return.
        (table (gnc:make-html-table))
        (document (gnc:make-html-document)))

    (gnc:html-document-set-title!
     document (string-append
               report-title
               (format #f " ~a" (qof-print-date to-date))))

    ;(gnc:debug "accounts" accounts)
    (if (not (null? accounts))
        (let* ((commodity-list (gnc:accounts-get-commodities
                                (gnc-accounts-and-all-descendants accounts)
                                currency))
               (pricedb (gnc-pricedb-get-db (gnc-get-current-book)))
	       (exchange-fn (gnc:case-exchange-fn price-source currency to-date))
               (price-fn
                (case price-source
                  ((weighted-average average-cost)
                   (lambda (foreign date)
                    (cons #f (gnc-numeric-div
                               (gnc:gnc-monetary-amount
                                  (exchange-fn (gnc:make-gnc-monetary foreign
                                                  (gnc-numeric-create 10000 1))
                                                  currency))
                               (gnc-numeric-create 10000 1)
                               GNC-DENOM-AUTO
                               (logior (GNC-DENOM-SIGFIGS 5) GNC-RND-ROUND)))))
                  ((pricedb-latest)
                   (lambda (foreign date)
                     (let* ((price
                             (gnc-pricedb-lookup-latest-any-currency
                              pricedb foreign))
                            (fn (if (and price (> (length price) 0))
                                    (let* ((the_price
                                            (if (gnc-commodity-equiv
                                                 foreign
                                                 (gnc-price-get-commodity (car price)))
                                                (car price)
                                                (gnc-price-invert (car price))))
                                           (v (gnc-price-get-value the_price)))
                                          (gnc-price-ref (car price))
                                          (cons (car price) v))
                                        (cons #f (gnc-numeric-zero)))))
                       (if price (gnc-price-list-destroy price))
                       fn)))
                  ((pricedb-before)
                   (lambda (foreign date)
                     (let ((price (gnc-pricedb-lookup-nearest-before-any-currency-t64
                                   pricedb foreign (time64CanonicalDayTime date))))
                       (cond
                        ((null? price) (cons #f 0))
                        (else (let ((p (car price)))
                                (gnc-price-ref p)
                                (gnc-price-list-destroy price)
                                (cons p (gnc-price-get-value p))))))))
                  ((pricedb-nearest)
                   (lambda (foreign date)
                     (let*  ((price
                             (gnc-pricedb-lookup-nearest-in-time-any-currency-t64
                              pricedb foreign (time64CanonicalDayTime date)))
                            (fn (if (and price (> (length price) 0))
                                    (let* ((v (gnc-price-get-value (car price))))
                                           (gnc-price-ref (car price))
                                           (cons (car price) v))
                                         (cons #f (gnc-numeric-zero)))))
                       (if price (gnc-price-list-destroy price))
                       fn))))))

          (gnc:html-table-set-col-headers!
           table
           (list (G_ "Account")
                 (G_ "Symbol")
                 (G_ "Listing")
                 (G_ "Units")
                 (G_ "Price")
                 (G_ "Value")))

          (table-add-stock-rows
           table accounts to-date currency
           exchange-fn price-fn include-empty collector)

          (gnc:html-table-append-row/markup!
           table
           "grand-total"
           (list
            (gnc:make-html-table-cell/size
             1 6 (gnc:make-html-text (gnc:html-markup-hr)))))

          (collector
           'format
           (lambda (currency amount)
             (gnc:html-table-append-row/markup!
              table
              "grand-total"
              (list (gnc:make-html-table-cell/markup
                     "total-label-cell" (G_ "Total"))
                    (gnc:make-html-table-cell/size/markup
                     1 5 "total-number-cell"
                     (gnc:make-gnc-monetary currency amount)))))
           #f)

          (gnc:html-document-add-object! document table))

                                        ;if no accounts selected.
        (gnc:html-document-add-object!
         document
	 (gnc:html-make-no-account-warning
	  report-title (gnc:report-id report-obj))))

    (gnc:report-finished)
    document)))

(gnc:define-report
 'version 1
 'name reportname
 'report-guid "4a6b82e8678c4f3d9e85d9f09634ca89"
 'menu-path (list gnc:menuname-asset-liability)
 'options-generator options-generator
 'renderer portfolio-renderer)
