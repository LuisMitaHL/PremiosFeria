import { describe, it, expect } from 'vitest';
import { render, screen } from '@testing-library/react';
import DynamicIcon from './DynamicIcon';

// The columns named `emoji` on communities and rewards hold Lucide icon names,
// not emoji characters (see the glossary). Rows seeded before that change still
// hold real emoji, so this component has to serve both. The fallback is the
// reason old events keep rendering.

describe('DynamicIcon', () => {
    it('renders the Lucide icon when the name matches one', () => {
        const { container } = render(<DynamicIcon name="Gift" />);

        expect(container.querySelector('svg')).toBeInTheDocument();
    });

    it('falls back to rendering the raw value when it is not an icon name', () => {
        const { container } = render(<DynamicIcon name="BookOpenNotARealIcon" />);

        expect(container.querySelector('svg')).not.toBeInTheDocument();
        expect(screen.getByText('BookOpenNotARealIcon')).toBeInTheDocument();
    });

    it('still renders legacy emoji values stored before the migration to icon names', () => {
        const { container } = render(<DynamicIcon name="B" />);

        // A single letter is not a Lucide export, so it takes the text path.
        expect(container.querySelector('svg')).not.toBeInTheDocument();
        expect(screen.getByText('B')).toBeInTheDocument();
    });

    it('applies the class name on both the icon and the fallback path', () => {
        const { container: iconContainer } = render(
            <DynamicIcon name="Gift" className="reward-icon" />
        );
        expect(iconContainer.querySelector('.reward-icon')).toBeInTheDocument();

        const { container: textContainer } = render(
            <DynamicIcon name="NotAnIcon" className="reward-icon" />
        );
        expect(textContainer.querySelector('.reward-icon')).toBeInTheDocument();
    });

    it('sizes the fallback text to match the requested icon size', () => {
        render(<DynamicIcon name="NotAnIcon" size={48} />);

        expect(screen.getByText('NotAnIcon')).toHaveStyle({ fontSize: '48px' });
    });
});
