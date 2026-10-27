'use client';

import { useEffect, useRef, useState } from 'react';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Avatar, AvatarFallback, AvatarImage } from '@/components/ui/avatar';
import { PanelError } from '@/components/data/PanelError';
import { Section } from './ui/Section';

interface Me {
  username: string;
  avatarUrl: string | null;
  fullName: string | null;
  email: string | null;
}

export function ProfilePanel() {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [me, setMe] = useState<Me | null>(null);
  const [loading, setLoading] = useState(true);

  const [fullName, setFullName] = useState('');
  const [email, setEmail] = useState('');
  const [savingProfile, setSavingProfile] = useState(false);
  const [profileError, setProfileError] = useState<string | null>(null);

  const [uploadingAvatar, setUploadingAvatar] = useState(false);
  const [avatarError, setAvatarError] = useState<string | null>(null);

  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [changingPassword, setChangingPassword] = useState(false);
  const [passwordError, setPasswordError] = useState<string | null>(null);
  const [passwordSaved, setPasswordSaved] = useState(false);

  useEffect(() => {
    void (async () => {
      const res = await fetch('/api/me');
      const data = await res.json().catch(() => null);
      setLoading(false);
      if (!res.ok || !data) return;
      setMe(data);
      setFullName(data.fullName ?? '');
      setEmail(data.email ?? '');
    })();
  }, []);

  const saveProfile = async () => {
    setSavingProfile(true);
    setProfileError(null);
    const res = await fetch('/api/me', {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ fullName, email }),
    });
    const data = await res.json().catch(() => ({}));
    setSavingProfile(false);
    if (!res.ok) {
      setProfileError(data.error ?? 'Falha ao salvar');
      return;
    }
    setMe((prev) => (prev ? { ...prev, fullName: data.fullName, email: data.email } : prev));
  };

  const pickPhoto = () => fileInputRef.current?.click();

  const onPhotoSelected = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    e.target.value = '';
    if (!file) return;

    setUploadingAvatar(true);
    setAvatarError(null);
    try {
      const dataUrl = await new Promise<string>((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result as string);
        reader.onerror = () => reject(reader.error);
        reader.readAsDataURL(file);
      });
      const res = await fetch('/api/me/avatar', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ dataUrl }),
      });
      const data = await res.json().catch(() => ({}));
      if (!res.ok) {
        setAvatarError(data.error ?? 'Falha ao enviar a foto');
        return;
      }
      setMe((prev) => (prev ? { ...prev, avatarUrl: data.avatarUrl } : prev));
    } finally {
      setUploadingAvatar(false);
    }
  };

  const removePhoto = async () => {
    setUploadingAvatar(true);
    setAvatarError(null);
    const res = await fetch('/api/me/avatar', { method: 'DELETE' });
    const data = await res.json().catch(() => ({}));
    setUploadingAvatar(false);
    if (!res.ok) {
      setAvatarError(data.error ?? 'Falha ao remover a foto');
      return;
    }
    setMe((prev) => (prev ? { ...prev, avatarUrl: data.avatarUrl } : prev));
  };

  const changePassword = async () => {
    setPasswordError(null);
    setPasswordSaved(false);
    if (newPassword !== confirmPassword) {
      setPasswordError('as senhas novas não coincidem');
      return;
    }
    setChangingPassword(true);
    const res = await fetch('/api/me/password', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ currentPassword, newPassword }),
    });
    const data = await res.json().catch(() => ({}));
    setChangingPassword(false);
    if (!res.ok) {
      setPasswordError(data.error ?? 'Falha ao trocar a senha');
      return;
    }
    setCurrentPassword('');
    setNewPassword('');
    setConfirmPassword('');
    setPasswordSaved(true);
  };

  if (loading || !me) {
    return <Section eyebrow="Perfil">{loading ? 'Carregando…' : null}</Section>;
  }

  const displayName = me.fullName || me.username;
  const initials = displayName.slice(0, 1).toUpperCase();

  return (
    <div className="flex flex-col gap-4">
      <Section eyebrow="Perfil">
        {avatarError && <PanelError>{avatarError}</PanelError>}

        <div className="flex flex-wrap items-center gap-4">
          <Avatar className="size-20">
            <AvatarImage src={me.avatarUrl ?? undefined} alt={displayName} />
            <AvatarFallback className="text-xl">{initials}</AvatarFallback>
          </Avatar>

          <input
            ref={fileInputRef}
            type="file"
            accept="image/png,image/jpeg,image/webp,image/gif"
            className="hidden"
            onChange={(e) => void onPhotoSelected(e)}
          />

          <div className="flex gap-2">
            <Button
              type="button"
              variant="outline"
              disabled={uploadingAvatar}
              onClick={pickPhoto}
            >
              {uploadingAvatar ? 'Enviando…' : 'Colocar foto'}
            </Button>
            {me.avatarUrl && (
              <Button
                type="button"
                variant="outline"
                disabled={uploadingAvatar}
                onClick={() => void removePhoto()}
              >
                Remover
              </Button>
            )}
          </div>
        </div>

        {profileError && <PanelError>{profileError}</PanelError>}

        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-nome">Nome completo</Label>
            <Input
              id="perfil-nome"
              value={fullName}
              onChange={(e) => setFullName(e.target.value)}
              placeholder="Seu nome completo"
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-email">E-mail</Label>
            <Input
              id="perfil-email"
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="voce@exemplo.com"
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-usuario">Usuário</Label>
            <Input id="perfil-usuario" value={me.username} disabled readOnly />
          </div>

          <Button
            type="button"
            className="self-start"
            disabled={savingProfile}
            onClick={() => void saveProfile()}
          >
            {savingProfile ? 'Salvando…' : 'Salvar'}
          </Button>
        </div>
      </Section>

      <Section eyebrow="Senha">
        {passwordError && <PanelError>{passwordError}</PanelError>}
        {passwordSaved && !passwordError && (
          <p className="text-sm text-ink-mid">Senha alterada.</p>
        )}

        <div className="flex flex-col gap-3">
          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-senha-atual">Senha atual</Label>
            <Input
              id="perfil-senha-atual"
              type="password"
              value={currentPassword}
              onChange={(e) => setCurrentPassword(e.target.value)}
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-senha-nova">Nova senha</Label>
            <Input
              id="perfil-senha-nova"
              type="password"
              value={newPassword}
              onChange={(e) => setNewPassword(e.target.value)}
              placeholder="mín. 8 caracteres"
            />
          </div>

          <div className="flex flex-col gap-1.5">
            <Label htmlFor="perfil-senha-confirmar">Confirmar nova senha</Label>
            <Input
              id="perfil-senha-confirmar"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
            />
          </div>

          <Button
            type="button"
            className="self-start"
            disabled={changingPassword || !currentPassword || !newPassword}
            onClick={() => void changePassword()}
          >
            {changingPassword ? 'Trocando…' : 'Trocar senha'}
          </Button>
        </div>
      </Section>
    </div>
  );
}
