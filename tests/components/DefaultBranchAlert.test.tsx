import { afterEach, describe, expect, it } from 'vitest';
import { cleanup, render, screen } from '@testing-library/react';
import { DefaultBranchAlert } from '@/components/pulls/DefaultBranchAlert';

afterEach(() => {
  cleanup();
});

describe('DefaultBranchAlert', () => {
  it('renders nothing when no default branch is failing', () => {
    const { container } = render(
      <DefaultBranchAlert
        branches={[
          { repo: 'acme/repo-1', branch: 'main', ci: 'passing' },
          { repo: 'acme/repo-2', branch: 'main', ci: 'none' },
          { repo: 'acme/repo-3', branch: 'main', ci: 'unknown' },
        ]}
      />,
    );
    expect(container).toBeEmptyDOMElement();
  });

  it('titles the warning so it reads as a red main branch', () => {
    render(<DefaultBranchAlert branches={[{ repo: 'acme/repo-4', branch: 'main', ci: 'failing' }]} />);
    expect(screen.getByRole('alert')).toHaveTextContent('CI vermelho na branch principal');
  });

  it('links a failing repository to its Actions runs on the default branch', () => {
    render(<DefaultBranchAlert branches={[{ repo: 'acme/repo-4', branch: 'main', ci: 'failing' }]} />);
    expect(screen.getByRole('link', { name: 'acme/repo-4 · main' })).toHaveAttribute(
      'href',
      'https://github.com/acme/repo-4/actions?query=branch%3Amain',
    );
  });

  it('encodes a branch name with a slash in the Actions query', () => {
    render(
      <DefaultBranchAlert branches={[{ repo: 'acme/repo-4', branch: 'release/1.0', ci: 'failing' }]} />,
    );
    expect(screen.getByRole('link', { name: 'acme/repo-4 · release/1.0' })).toHaveAttribute(
      'href',
      'https://github.com/acme/repo-4/actions?query=branch%3Arelease%2F1.0',
    );
  });

  it('does not show a branch whose CI is still running', () => {
    render(
      <DefaultBranchAlert
        branches={[
          { repo: 'acme/repo-4', branch: 'main', ci: 'failing' },
          { repo: 'acme/repo-5', branch: 'main', ci: 'running' },
        ]}
      />,
    );
    expect(screen.queryByText(/acme\/repo-5/)).not.toBeInTheDocument();
  });

  it('lists every failing repository', () => {
    render(
      <DefaultBranchAlert
        branches={[
          { repo: 'acme/repo-4', branch: 'main', ci: 'failing' },
          { repo: 'acme/repo-6', branch: 'develop', ci: 'failing' },
        ]}
      />,
    );
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
  });

  it('shows an invalid repository name as text without a link', () => {
    render(<DefaultBranchAlert branches={[{ repo: 'not a repo', branch: 'main', ci: 'failing' }]} />);
    expect(screen.getByText('not a repo · main')).toBeInTheDocument();
  });

  it('gives an invalid repository name no link', () => {
    render(<DefaultBranchAlert branches={[{ repo: 'not a repo', branch: 'main', ci: 'failing' }]} />);
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });
});
