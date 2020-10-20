@product
Feature: APT sources are correctly configured
  As a Tails user
  I want APT to be configured to use hidden services

  Scenario: APT sources are configured correctly
    Given a computer
    And I start Tails from DVD with network unplugged and genuine APT sources and I login
    Then the only hosts in APT sources are "vwakviie2ienjx6t.onion,sgvtcaew4bxjd7ln.onion,umjqavufhoix3smyq6az2sx4istmuvsgmz4bq5u5x56rnayejoo6l2qd.onion,sdscoq7snqtznauu.onion"
    And no proposed-updates APT suite is enabled
    And no experimental APT suite is enabled for deb.torproject.org
