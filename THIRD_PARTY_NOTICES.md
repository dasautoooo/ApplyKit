# Third-Party Notices

## ats-scrapers

ApplyKit's ATS-specific endpoint resolution and field mappings are adapted from
[kalil0321/ats-scrapers](https://github.com/kalil0321/ats-scrapers).

Specifically, the following are ports or adaptations of that project's work:

- The Workday pagination algorithm in
  `ApplyKit/Infrastructure/Discovery/Providers/WorkdayProvider.swift` — the
  20-item page cap, the 2000-result query cap with recursive facet subdivision
  (`jobFamilyGroup` → `timeType` → `locations` → `workerSubType`), and the
  per-job detail enrichment that resolves `"N Locations"` rollups — is ported
  from `src/ats_scrapers/scrapers/workday.py`.
- Job-board list endpoints and response field mappings for Greenhouse, Lever,
  Ashby, SmartRecruiters, Workable, Recruitee, Personio, BambooHR, Breezy,
  JazzHR, and Teamtailor.
- Career-site endpoints and field mappings for Amazon, Apple, Uber, TikTok,
  ByteDance, Google, Tesla, and Meta.
- The Eightfold AI search-endpoint and pagination logic in
  `ApplyKit/Infrastructure/Discovery/Providers/EightfoldProvider.swift`, ported
  from `src/ats_scrapers/scrapers/eightfold.py`.
- The SuccessFactors recruiting-marketing RSS feed parsing in
  `ApplyKit/Infrastructure/Discovery/Providers/SuccessFactorsProvider.swift`,
  ported from `src/ats_scrapers/scrapers/successfactors.py`.
- The iCIMS job-card HTML pattern and pagination in
  `ApplyKit/Infrastructure/Discovery/Providers/ICIMSProvider.swift`, ported
  from `src/ats_scrapers/scrapers/icims.py`.
- The Cornerstone OnDemand JWT-then-JSON session flow in
  `ApplyKit/Infrastructure/Discovery/Providers/CornerstoneProvider.swift`,
  ported from `src/ats_scrapers/scrapers/cornerstone.py`.
- `ApplyKit/Resources/known-boards.tsv` — the bundled company-name → tenant
  directory — is generated from that project's `ats-companies/*.csv` dataset
  (Workday, iCIMS, Cornerstone, SuccessFactors, Avature, Eightfold, Phenom),
  reshaped into ApplyKit's `TrackedBoard` fields. Names that mapped to more
  than one company were dropped.
- The Phenom `refineSearch` widget payload, CSRF handshake, and pagination in
  `ApplyKit/Infrastructure/Discovery/Providers/PhenomProvider.swift`, ported
  from `src/ats_scrapers/scrapers/phenom.py`.
- The Avature job-anchor/container extraction strategy in
  `ApplyKit/Infrastructure/Discovery/Providers/AvatureProvider.swift`,
  adapted from `src/ats_scrapers/scrapers/avature.py` (reimplemented as an
  in-page JS query run through `BrowserFetcher` rather than the Python
  version's BeautifulSoup + httpcloak/Browserbase fallback chain).

MIT License

Copyright (c) 2026 Kalil Bouzigues

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
