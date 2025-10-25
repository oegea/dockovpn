# PRIVACY POLICY

## ABOUT THIS FORK

This is a community-maintained fork of the original DockOvpn project. The fork is maintained by a single individual with the primary goal of keeping the Docker image up-to-date with the latest security patches and dependency updates to prevent potential security vulnerabilities.

## HOW WE USE DATA

We do not collect any personally identifiable information. We do not sell any data to advertisers or third parties.

### Privacy Improvements

One of the key motivations behind creating this fork was to enhance privacy by eliminating any potential collection of server IP addresses. While the original project's authors used a proprietary IP detection service with benevolent intentions (to avoid relying on third-party services that might collect data), this approach required users to trust that server IP addresses were not being logged or stored.

This fork has been modified to use privacy-focused IP detection services from reputable providers such as Cloudflare and AWS. These services offer several privacy advantages:

- **Anonymity through scale**: Even if these providers maintain access logs, your server's IP address will be aggregated among millions of other users making similar requests across countless use cases
- **Context obscurity**: These large-scale providers cannot determine why an IP address is being detected, making it impossible to build a database specifically of servers running this VPN software
- **Industry reputation**: Both Cloudflare and AWS have established privacy policies and reputations to maintain

By leveraging these widely-used infrastructure services, we eliminate the need to trust any single individual or small project with potentially sensitive information about your server deployment.

We believe transparency and privacy by design are fundamental principles, especially for security-focused software like VPN servers. 
