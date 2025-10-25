# PRIVACY POLICY

## ABOUT THIS FORK

This is a community-maintained fork of the original DockOvpn project. The fork is maintained by a single individual with the primary goal of keeping the Docker image up-to-date with the latest security patches and dependency updates to prevent potential security vulnerabilities.

## HOW WE USE DATA

We do not collect any personally identifiable information. We do not sell any data to advertisers or third parties.

### Architectural Approach to Privacy

This fork takes a different architectural approach to IP address detection. Instead of using a dedicated service, it relies on privacy-focused IP detection services from large-scale infrastructure providers such as Cloudflare and AWS.

**Important clarification**: This is not a criticism of the original project or its authors. It's simply a different design philosophy that the fork maintainer feels more comfortable with as a preventive measure. Both approaches have their merits.

The rationale behind this architectural choice:

- **Anonymity through scale**: These providers handle millions of requests daily across countless use cases, making individual server IP addresses indistinguishable in aggregate logs
- **Context obscurity**: Large-scale infrastructure providers cannot determine the specific purpose of IP detection requests, preventing the possibility of building targeted databases
- **Established privacy policies**: These providers have publicly documented privacy commitments and reputations to maintain

This approach reflects a personal preference for distributing trust across established infrastructure providers rather than relying on any single service. It's a defensive design decision, not an indication of any actual privacy concerns with the original implementation.

While we appreciate the good intentions behind creating a dedicated IP detection service that claims not to store logs, the inherent challenge is that only the service operators can truly verify this claim. This is not an accusation that logging has occurred—it's simply an acknowledgment that verification requires trust. The fork maintainer feels more comfortable using well-established infrastructure providers where the service purpose is general rather than VPN-specific. For details on the services used, see our implementation in the [codebase](https://github.com/oegea/dockovpn/blob/master/scripts/start.sh).

We believe transparency about these architectural decisions is important for security-focused software like VPN servers. 
