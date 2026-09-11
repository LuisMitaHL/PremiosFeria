import * as LucideIcons from 'lucide-react';

export default function DynamicIcon({ name, size = 24, className = '', ...props }) {
    // If name is a lucide icon name, render it, else maybe it's still an old emoji in the DB
    const IconComponent = LucideIcons[name];

    if (IconComponent) {
        return <IconComponent size={size} className={className} {...props} />;
    }

    // Fallback: render text as it might be an old emoji like '📚'
    return <span className={className} style={{ fontSize: size }} {...props}>{name}</span>;
}
