import { redirect } from 'next/navigation';

// The panels moved to the home page; this keeps old bookmarks working.
export default function WorkspaceRedirect(): never {
  redirect('/');
}
